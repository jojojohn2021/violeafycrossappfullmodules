/**
 * LeafyEarth Pre-Order Booking Module — Domain Service & Server-Side Firestore Repository.
 *
 * Collections accessed exclusively via Firebase Admin SDK:
 *   - products/{productId}                   (read-only; checks `preorderactive === true`)
 *   - preorders/{preorderId}                 (pre-order bookings; NEVER stored in `sales_orders`)
 *   - payment_allocations/{checkoutRef}      (payment split between regular sales & pre-order advances)
 *   - preorder_idempotency/{lockId}          (idempotency locks for booking creation)
 *   - preorder_events/{eventId}              (append-only audit log)
 *   - courier_agencies/{agencyId}            (optional read-only courier options)
 */

import crypto from 'crypto';
import {
  ALLOWED_STATUS_TRANSITIONS,
  DEFAULT_COURIER_AGENTS,
  DEFAULT_PREORDER_CONFIG,
  type PaymentAllocationDto,
  type PreorderBookingDto,
  type PreorderBookingStatus,
  type PreorderConfig,
  type PreorderConversionStatus,
  type PreorderDeliveryAddressDto,
  PreorderDomainError,
  type PreorderPaymentAllocationItemDto,
  type PreorderPaymentStatus,
  type PreorderPaymentType,
  type PreorderPaymentTypeLabel,
} from './preorderTypes';

export const COLLECTIONS = {
  PRODUCTS: 'products',
  PREORDERS: 'preorders',
  SALES_ORDERS: 'sales_orders',
  PAYMENT_ALLOCATIONS: 'payment_allocations',
  IDEMPOTENCY: 'preorder_idempotency',
  EVENTS: 'preorder_events',
  COURIER_AGENCIES: 'courier_agencies',
} as const;

const SAFE_ID_RE = /^[A-Za-z0-9_\-]{1,128}$/;
const DATE_YYYY_MM_DD_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function isValidId(id: unknown): id is string {
  return typeof id === 'string' && SAFE_ID_RE.test(id.trim());
}

export function roundMoney(val: number): number {
  return Math.round((val + Number.EPSILON) * 100) / 100;
}

/**
 * NON-NEGOTIABLE RULE:
 * Eligibility is exclusively based on `products.{id}.preorderactive === true` (strictly Boolean true).
 * Missing, null, undefined, false, "true", 1, or any non-boolean values are NOT eligible.
 */
export function isProductPreorderEligible(product: unknown): boolean {
  if (!product || typeof product !== 'object') return false;
  const record = product as Record<string, unknown>;
  return record.preorderactive === true;
}

export function sanitizeNotes(notes: unknown, maxLen = 500): string {
  if (notes === null || notes === undefined) return '';
  return String(notes)
    .replace(/<[^>]*>/g, '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .trim()
    .slice(0, maxLen);
}

/** Formats a UTC timestamp into YYYY-MM-DD in the configured business timezone. */
export function formatLocalDate(utcDate: Date, offsetMinutes = 330): {
  dateLocal: string;
  weekday: number;
  hourLocal: number;
} {
  const shifted = new Date(utcDate.getTime() + offsetMinutes * 60_000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const d = String(shifted.getUTCDate()).padStart(2, '0');
  return {
    dateLocal: `${y}-${m}-${d}`,
    weekday: shifted.getUTCDay(),
    hourLocal: shifted.getUTCHours(),
  };
}

/** Validates that expectedDeliveryDate is a valid YYYY-MM-DD calendar date strictly in the future. */
export function validateFutureDeliveryDate(
  rawDate: unknown,
  now: Date = new Date(),
  offsetMinutes = 330
): string {
  if (typeof rawDate !== 'string' || !rawDate.trim()) {
    throw new PreorderDomainError('VALIDATION_ERROR', 'Expected Date of Delivery is required.', 400);
  }
  const trimmed = rawDate.trim();
  const match = DATE_YYYY_MM_DD_RE.exec(trimmed);
  if (!match) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      'Expected Date of Delivery must be in YYYY-MM-DD format.',
      400
    );
  }
  const year = parseInt(match[1], 10);
  const month = parseInt(match[2], 10);
  const day = parseInt(match[3], 10);
  const check = new Date(Date.UTC(year, month - 1, day));
  if (
    check.getUTCFullYear() !== year ||
    check.getUTCMonth() + 1 !== month ||
    check.getUTCDate() !== day
  ) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      'Expected Date of Delivery is not a valid calendar date.',
      400
    );
  }

  const { dateLocal: todayLocal } = formatLocalDate(now, offsetMinutes);
  if (trimmed <= todayLocal) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      'Expected Date of Delivery must be a future date (after today).',
      400
    );
  }
  return trimmed;
}

/** Normalizes payment type from 'full' | 'Full Amount' | 'partial' | 'Partial Payment'. */
export function normalizePaymentType(raw: unknown): {
  paymentType: PreorderPaymentType;
  paymentTypeLabel: PreorderPaymentTypeLabel;
} {
  if (typeof raw !== 'string' || !raw.trim()) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      'Payment option must be Full Amount or Partial Payment.',
      400
    );
  }
  const normalized = raw.trim().toLowerCase();
  if (normalized === 'full' || normalized === 'full amount' || normalized === 'full_amount') {
    return { paymentType: 'full', paymentTypeLabel: 'Full Amount' };
  }
  if (normalized === 'partial' || normalized === 'partial payment' || normalized === 'partial_payment') {
    return { paymentType: 'partial', paymentTypeLabel: 'Partial Payment' };
  }
  throw new PreorderDomainError(
    'VALIDATION_ERROR',
    'Invalid payment option. Choose Full Amount or Partial Payment.',
    400
  );
}

/** Normalizes Gift Wrap input (boolean or 'Yes'/'No'). */
export function normalizeGiftWrap(raw: unknown): boolean {
  if (raw === undefined || raw === null || raw === '') return false;
  if (typeof raw === 'boolean') return raw;
  if (typeof raw === 'string') {
    const lower = raw.trim().toLowerCase();
    if (lower === 'yes' || lower === 'true') return true;
    if (lower === 'no' || lower === 'false') return false;
  }
  throw new PreorderDomainError('VALIDATION_ERROR', 'Gift Wrap must be Yes or No (boolean).', 400);
}

/** Validates Preferred Courier Agent against the restricted combo box list. */
export function validatePreferredCourierAgent(
  raw: unknown,
  allowedAgents: string[] = DEFAULT_COURIER_AGENTS
): string {
  const sanitized = sanitizeNotes(raw, 100);
  if (!sanitized) {
    throw new PreorderDomainError('VALIDATION_ERROR', 'Preferred Courier Agent is required.', 400);
  }
  const match = allowedAgents.find(
    (agent) => agent.toLowerCase() === sanitized.toLowerCase()
  );
  if (!match) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      `Preferred Courier Agent must be one of: ${allowedAgents.join(', ')}.`,
      400
    );
  }
  return match;
}

/** Normalizes a delivery/shipping address object or flat fields into structured + flat fields for the preorders table. */
export function normalizeDeliveryAddress(raw: unknown): {
  deliveryAddress: PreorderDeliveryAddressDto | null;
  shippingAddress: PreorderDeliveryAddressDto | null;
  deliveryAddressName: string;
  deliveryAddressMobile: string;
  deliveryAddressEmail: string;
  deliveryAddressLine: string;
  deliveryCity: string;
  deliveryDistrict: string;
  deliveryState: string;
  deliveryPincode: string;
  formattedDeliveryAddress: string;
} {
  if (!raw || typeof raw !== 'object') {
    return {
      deliveryAddress: null,
      shippingAddress: null,
      deliveryAddressName: '',
      deliveryAddressMobile: '',
      deliveryAddressEmail: '',
      deliveryAddressLine: '',
      deliveryCity: '',
      deliveryDistrict: '',
      deliveryState: '',
      deliveryPincode: '',
      formattedDeliveryAddress: '',
    };
  }
  const obj = raw as Record<string, unknown>;
  const id = sanitizeNotes(obj.id ?? obj.addressId, 128);
  const name = sanitizeNotes(
    obj.name ?? obj.deliveryAddressName ?? obj.customerName ?? obj.recipientName,
    120
  );
  const mobileNumber = sanitizeNotes(
    obj.mobileNumber ?? obj.deliveryAddressMobile ?? obj.mobile ?? obj.phone ?? obj.contactNo,
    30
  );
  const email = sanitizeNotes(obj.email ?? obj.deliveryAddressEmail ?? obj.customerEmail, 150);
  const addressLine = sanitizeNotes(
    obj.addressLine ?? obj.deliveryAddressLine ?? obj.address ?? obj.street ?? obj.line1,
    300
  );
  const city = sanitizeNotes(obj.city ?? obj.deliveryCity ?? obj.town ?? obj.locality, 100);
  const district = sanitizeNotes(obj.district ?? obj.deliveryDistrict, 100);
  const state = sanitizeNotes(obj.state ?? obj.deliveryState, 100);
  const pincode = sanitizeNotes(
    obj.pincode ?? obj.deliveryPincode ?? obj.pinCode ?? obj.zipCode ?? obj.postalCode,
    20
  );

  const hasContent = Boolean(
    addressLine || city || district || state || pincode || name || mobileNumber
  );
  if (!hasContent) {
    return {
      deliveryAddress: null,
      shippingAddress: null,
      deliveryAddressName: '',
      deliveryAddressMobile: '',
      deliveryAddressEmail: '',
      deliveryAddressLine: '',
      deliveryCity: '',
      deliveryDistrict: '',
      deliveryState: '',
      deliveryPincode: '',
      formattedDeliveryAddress: '',
    };
  }

  const locationParts = [addressLine, city, district, state].filter(Boolean);
  let formatted = locationParts.join(', ');
  if (pincode) {
    formatted = formatted ? `${formatted} - ${pincode}` : pincode;
  }
  if (name) {
    const header = mobileNumber ? `${name} (${mobileNumber})` : name;
    formatted = formatted ? `${header}, ${formatted}` : header;
  }

  const dto: PreorderDeliveryAddressDto = {
    ...(id ? { id } : {}),
    name,
    mobileNumber,
    ...(email ? { email } : {}),
    addressLine,
    city,
    district,
    state,
    pincode,
    formattedAddress: formatted,
  };

  return {
    deliveryAddress: dto,
    shippingAddress: dto,
    deliveryAddressName: name,
    deliveryAddressMobile: mobileNumber,
    deliveryAddressEmail: email,
    deliveryAddressLine: addressLine,
    deliveryCity: city,
    deliveryDistrict: district,
    deliveryState: state,
    deliveryPincode: pincode,
    formattedDeliveryAddress: formatted,
  };
}

/** Computes server-authoritative unit price (Online Price), MRP, GST, and total product value. */
export function computeAuthoritativePricing(product: Record<string, any>, quantity: number) {
  const rawOffer =
    product.offerPrice !== undefined && product.offerPrice !== null ? Number(product.offerPrice) : NaN;
  const rawOnline = Number(product.onlinePrice ?? 0);
  const onlinePrice = Number.isFinite(rawOffer) && rawOffer > 0 ? rawOffer : rawOnline;

  if (!Number.isFinite(onlinePrice) || onlinePrice <= 0) {
    throw new PreorderDomainError('VALIDATION_ERROR', 'Product does not have a valid server price.', 422);
  }

  const rawMrp = Number(product.mrp ?? product.shopPrice ?? onlinePrice);
  const mrp = Number.isFinite(rawMrp) && rawMrp >= onlinePrice ? rawMrp : onlinePrice;
  const rawGst = Number(product.gstPercentage ?? product.gstRate ?? 0);
  const gstPercentage = Number.isFinite(rawGst) && rawGst >= 0 ? rawGst : 0;

  const onlinePriceSnapshot = roundMoney(onlinePrice);
  const totalProductValue = roundMoney(onlinePriceSnapshot * quantity);

  return {
    onlinePriceSnapshot,
    unitPriceSnapshot: onlinePriceSnapshot,
    mrpSnapshot: roundMoney(mrp),
    gstPercentageSnapshot: roundMoney(gstPercentage),
    totalProductValue,
  };
}

/**
 * Validates and computes Booking Advance and Remaining Balance according to Section 3.1:
 * - Full Amount: Booking Advance = 100% of totalProductValue, Remaining Balance = 0
 * - Partial Payment: Booking Advance between 10% and 100% of totalProductValue, Remaining Balance = totalProductValue - bookingAdvance
 */
export function validateAndComputeAdvance(params: {
  onlinePriceSnapshot: number;
  quantity: number;
  paymentType: PreorderPaymentType;
  rawBookingAdvance?: unknown;
  config?: PreorderConfig;
}): {
  totalProductValue: number;
  minBookingAdvance: number;
  maxBookingAdvance: number;
  bookingAdvance: number;
  remainingBalance: number;
} {
  const config = params.config || DEFAULT_PREORDER_CONFIG;
  const totalProductValue = roundMoney(params.onlinePriceSnapshot * params.quantity);
  const minBookingAdvance = roundMoney(totalProductValue * config.minAdvanceRatio);
  const maxBookingAdvance = roundMoney(totalProductValue * config.maxAdvanceRatio);

  if (params.paymentType === 'full') {
    if (
      params.rawBookingAdvance !== undefined &&
      params.rawBookingAdvance !== null &&
      params.rawBookingAdvance !== ''
    ) {
      if (typeof params.rawBookingAdvance === 'boolean') {
        throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid Booking Advance value.', 400);
      }
      const supplied = Number(params.rawBookingAdvance);
      if (!Number.isFinite(supplied) || Math.abs(roundMoney(supplied) - totalProductValue) > 0.01) {
        throw new PreorderDomainError(
          'VALIDATION_ERROR',
          `Full Amount booking advance must equal the full product value (₹${totalProductValue.toFixed(2)}).`,
          400
        );
      }
    }
    return {
      totalProductValue,
      minBookingAdvance,
      maxBookingAdvance,
      bookingAdvance: totalProductValue,
      remainingBalance: 0,
    };
  }

  // Partial Payment
  if (
    params.rawBookingAdvance === undefined ||
    params.rawBookingAdvance === null ||
    params.rawBookingAdvance === '' ||
    typeof params.rawBookingAdvance === 'boolean'
  ) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      'Booking Advance is required for Partial Payment.',
      400
    );
  }

  const parsed = Number(params.rawBookingAdvance);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      'Booking Advance must be a valid positive number.',
      400
    );
  }

  const bookingAdvance = roundMoney(parsed);
  if (bookingAdvance < minBookingAdvance - 0.001) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      `Booking Advance cannot be less than 10% of the product price (minimum ₹${minBookingAdvance.toFixed(2)}).`,
      400
    );
  }
  if (bookingAdvance > maxBookingAdvance + 0.001) {
    throw new PreorderDomainError(
      'VALIDATION_ERROR',
      `Booking Advance cannot exceed 100% of the product price (maximum ₹${maxBookingAdvance.toFixed(2)}).`,
      400
    );
  }

  const remainingBalance = roundMoney(Math.max(0, totalProductValue - bookingAdvance));
  return {
    totalProductValue,
    minBookingAdvance,
    maxBookingAdvance,
    bookingAdvance,
    remainingBalance,
  };
}

/**
 * Pure financial calculator implementing Section 5 (Mandatory GST, Invoice Value & Final Payment Rule):
 * - Regular Sales Subtotal = Sum of regular sales item values ONLY
 * - Regular Sales GST = Calculated on regular sales items ONLY
 * - Regular Invoice Grand Total = Regular Sales Subtotal + Delivery Fee - Discount (0 when no regular items)
 * - Total Pre-Order Booking Advance = Sum of pre-order Booking Advances
 * - Customer Grand Total Payable = Regular Invoice Grand Total + Total Pre-Order Booking Advance
 */
export function calculateCheckoutFinancials(params: {
  regularItems: Array<{ price: number; quantity: number; gstPercentage?: number }>;
  preorderItems: Array<{
    bookingAdvance: number;
    totalProductValue?: number;
    remainingBalance?: number;
  }>;
  deliveryFee?: number;
  discount?: number;
}) {
  let regularSalesSubtotal = 0;
  let regularSalesTaxableValue = 0;
  let regularSalesGst = 0;

  for (const item of params.regularItems || []) {
    const lineTotal = roundMoney(Math.max(0, Number(item.price || 0)) * Math.max(1, Number(item.quantity || 1)));
    const gstRate = Math.max(0, Number(item.gstPercentage ?? 0));
    const taxableValue = gstRate > 0 ? roundMoney(lineTotal / (1 + gstRate / 100)) : lineTotal;
    const gstAmount = roundMoney(lineTotal - taxableValue);

    regularSalesSubtotal = roundMoney(regularSalesSubtotal + lineTotal);
    regularSalesTaxableValue = roundMoney(regularSalesTaxableValue + taxableValue);
    regularSalesGst = roundMoney(regularSalesGst + gstAmount);
  }

  const hasRegularItems = (params.regularItems || []).length > 0 && regularSalesSubtotal > 0;
  const effectiveDeliveryFee = hasRegularItems ? roundMoney(Math.max(0, Number(params.deliveryFee || 0))) : 0;
  const effectiveDiscount = hasRegularItems ? roundMoney(Math.max(0, Number(params.discount || 0))) : 0;

  const regularInvoiceGrandTotal = hasRegularItems
    ? roundMoney(Math.max(0, regularSalesSubtotal + effectiveDeliveryFee - effectiveDiscount))
    : 0;

  let totalPreorderBookingAdvance = 0;
  let totalPreorderProductValue = 0;
  let totalPreorderRemainingBalance = 0;

  for (const po of params.preorderItems || []) {
    const adv = roundMoney(Math.max(0, Number(po.bookingAdvance || 0)));
    const prodVal = roundMoney(Math.max(adv, Number(po.totalProductValue ?? adv)));
    const remBal = roundMoney(
      po.remainingBalance !== undefined ? Math.max(0, Number(po.remainingBalance)) : Math.max(0, prodVal - adv)
    );
    totalPreorderBookingAdvance = roundMoney(totalPreorderBookingAdvance + adv);
    totalPreorderProductValue = roundMoney(totalPreorderProductValue + prodVal);
    totalPreorderRemainingBalance = roundMoney(totalPreorderRemainingBalance + remBal);
  }

  const customerGrandTotalPayable = roundMoney(regularInvoiceGrandTotal + totalPreorderBookingAdvance);

  return {
    regularSalesSubtotal,
    regularSalesTaxableValue,
    regularSalesGst,
    deliveryFee: effectiveDeliveryFee,
    discount: effectiveDiscount,
    regularInvoiceGrandTotal,
    totalPreorderBookingAdvance,
    totalPreorderProductValue,
    totalPreorderRemainingBalance,
    customerGrandTotalPayable,
  };
}

/** Checks whether a booking can currently be cancelled by the customer. */
export function canCustomerCancelBooking(booking: {
  bookingStatus: PreorderBookingStatus;
  conversionStatus?: PreorderConversionStatus;
  salesOrderId?: string | null;
}): { allowed: boolean; reason?: string } {
  if (booking.conversionStatus === 'converted' || booking.salesOrderId) {
    return {
      allowed: false,
      reason: 'Bookings already converted to a sales order cannot be cancelled directly.',
    };
  }
  if (!['pending_payment', 'confirmed'].includes(booking.bookingStatus)) {
    return {
      allowed: false,
      reason: `Bookings in '${booking.bookingStatus}' state cannot be cancelled by customer.`,
    };
  }
  return { allowed: true };
}

/** Validates whether an admin status transition is allowed. */
export function isValidStatusTransition(
  currentStatus: PreorderBookingStatus,
  nextStatus: PreorderBookingStatus
): boolean {
  if (currentStatus === nextStatus) return true;
  const allowed = ALLOWED_STATUS_TRANSITIONS[currentStatus] || [];
  return allowed.includes(nextStatus);
}

/** Formats an Eligible Product summary for the Pre-Order catalog. */
export function toEligibleProductDto(docId: string, data: Record<string, any>) {
  const rawOffer =
    data.offerPrice !== undefined && data.offerPrice !== null ? Number(data.offerPrice) : NaN;
  const onlinePrice = Number(data.onlinePrice ?? 0);
  const effectivePrice = Number.isFinite(rawOffer) && rawOffer > 0 ? rawOffer : onlinePrice;
  const mrp = Math.max(effectivePrice, Number(data.mrp ?? data.shopPrice ?? effectivePrice));
  const imageUrl =
    data.imageUrl ||
    data.image ||
    (Array.isArray(data.images) && data.images.length > 0 ? data.images[0] : null) ||
    null;

  return {
    id: docId,
    name: String(data.name || ''),
    sku: String(data.sku || ''),
    packingSize: String(data.packingSize || data.unit || ''),
    unit: String(data.unit || ''),
    onlinePrice,
    offerPrice: Number.isFinite(rawOffer) && rawOffer > 0 ? rawOffer : null,
    effectivePrice: roundMoney(effectivePrice),
    mrp: roundMoney(mrp),
    gstPercentage: Number(data.gstPercentage ?? 0),
    imageUrl: imageUrl ? String(imageUrl) : null,
    images: Array.isArray(data.images) ? data.images.map(String) : [],
    category: String(data.category || ''),
    brand: data.brand ? String(data.brand) : null,
    description: data.description ? String(data.description) : null,
    preorderactive: true,
    uniqueSpecs: [data.uniqueSpec1, data.uniqueSpec2, data.uniqueSpec3, data.uniqueSpec4]
      .filter((s) => typeof s === 'string' && s.trim().length > 0)
      .map((s) => String(s).trim()),
    rating: typeof data.rating === 'number' ? data.rating : null,
    reviewsCount: typeof data.reviewsCount === 'number' ? data.reviewsCount : null,
  };
}

export interface PreorderServiceDeps {
  adminDb: any;
  config?: PreorderConfig;
  now?: () => Date;
  onSalesOrderCreated?: (
    salesOrder: Record<string, any>
  ) => Promise<{ invoiceId?: string | null } | void>;
}

export function createPreorderService(deps: PreorderServiceDeps) {
  const { adminDb } = deps;
  const config = deps.config || DEFAULT_PREORDER_CONFIG;
  const getNow = deps.now || (() => new Date());

  function toBookingDto(data: Record<string, any>): PreorderBookingDto {
    const rawBookingStatus = String(data.bookingStatus || data.status || 'pending_payment') as PreorderBookingStatus;
    const rawPaymentStatus = String(data.paymentStatus || 'unpaid') as PreorderPaymentStatus;
    const paymentType: PreorderPaymentType =
      data.paymentType === 'partial' || data.paymentType === 'Partial Payment' ? 'partial' : 'full';
    const paymentTypeLabel: PreorderPaymentTypeLabel =
      paymentType === 'partial' ? 'Partial Payment' : 'Full Amount';

    const onlinePriceSnapshot = roundMoney(
      Number(data.onlinePriceSnapshot ?? data.unitPriceSnapshot ?? 0)
    );
    const quantity = Math.max(1, Number(data.quantity || 1));
    const totalProductValue = roundMoney(
      Number(data.totalProductValue ?? data.totalSnapshot ?? onlinePriceSnapshot * quantity)
    );
    const bookingAdvance = roundMoney(Number(data.bookingAdvance ?? totalProductValue));
    const initialBookingAdvance = roundMoney(
      Number(data.initialBookingAdvance ?? bookingAdvance)
    );
    const totalVerifiedPaid = roundMoney(
      data.totalVerifiedPaid !== undefined && data.totalVerifiedPaid !== null
        ? Number(data.totalVerifiedPaid)
        : rawPaymentStatus === 'paid'
        ? totalProductValue
        : rawPaymentStatus === 'partially_paid'
        ? bookingAdvance
        : 0
    );
    const remainingBalance = roundMoney(
      data.remainingBalance !== undefined && data.remainingBalance !== null
        ? Math.max(0, Number(data.remainingBalance))
        : Math.max(
            0,
            totalProductValue -
              (rawPaymentStatus === 'unpaid' ? bookingAdvance : totalVerifiedPaid)
          )
    );

    const salesOrderId = data.salesOrderId ? String(data.salesOrderId) : null;
    const salesOrderNumber = data.salesOrderNumber ? String(data.salesOrderNumber) : null;
    const salesInvoiceId = data.salesInvoiceId ? String(data.salesInvoiceId) : null;
    const conversionStatus: PreorderConversionStatus = data.conversionStatus
      ? (String(data.conversionStatus) as PreorderConversionStatus)
      : salesOrderId
      ? 'converted'
      : rawPaymentStatus === 'paid' && remainingBalance <= 0
      ? 'pending'
      : 'not_applicable';

    const cancelCheck = canCustomerCancelBooking({
      bookingStatus: rawBookingStatus,
      conversionStatus,
      salesOrderId,
    });

    const addrNorm = normalizeDeliveryAddress(
      data.deliveryAddress ?? data.shippingAddress ?? data
    );

    const lastPaymentReference =
      data.lastPaymentReference ||
      data.balancePaymentReference ||
      data.paymentReference ||
      null;

    return {
      preorderId: String(data.preorderId || data.id),
      userId: String(data.userId || ''),
      customerId: String(data.customerId || data.userId || ''),
      customerDisplayName: String(data.customerDisplayName || 'LeafyEarth Customer'),
      productId: String(data.productId || ''),
      productNameSnapshot: String(data.productNameSnapshot || ''),
      skuSnapshot: String(data.skuSnapshot || ''),
      packingSizeSnapshot: String(data.packingSizeSnapshot || ''),
      imageUrlSnapshot: data.imageUrlSnapshot ? String(data.imageUrlSnapshot) : null,
      quantity,
      onlinePriceSnapshot,
      mrpSnapshot: roundMoney(Number(data.mrpSnapshot || onlinePriceSnapshot)),
      gstPercentageSnapshot: roundMoney(Number(data.gstPercentageSnapshot || 0)),
      totalProductValue,
      paymentType,
      paymentTypeLabel,
      bookingAdvance,
      initialBookingAdvance,
      totalVerifiedPaid,
      remainingBalance,
      giftWrap: Boolean(data.giftWrap),
      specialSuggestion: String(data.specialSuggestion ?? data.notes ?? ''),
      expectedDeliveryDate: String(data.expectedDeliveryDate || ''),
      preferredCourierAgent: String(data.preferredCourierAgent || 'India Post'),
      deliveryAddress: addrNorm.deliveryAddress,
      shippingAddress: addrNorm.shippingAddress,
      deliveryAddressName: addrNorm.deliveryAddressName,
      deliveryAddressMobile: addrNorm.deliveryAddressMobile,
      deliveryAddressEmail: addrNorm.deliveryAddressEmail,
      deliveryAddressLine: addrNorm.deliveryAddressLine,
      deliveryCity: addrNorm.deliveryCity,
      deliveryDistrict: addrNorm.deliveryDistrict,
      deliveryState: addrNorm.deliveryState,
      deliveryPincode: addrNorm.deliveryPincode,
      formattedDeliveryAddress: addrNorm.formattedDeliveryAddress,
      currency: String(data.currency || config.currency),
      bookingStatus: rawBookingStatus,
      status: rawBookingStatus,
      paymentStatus: rawPaymentStatus,
      paymentReference: data.paymentReference ? String(data.paymentReference) : null,
      lastPaymentReference: lastPaymentReference ? String(lastPaymentReference) : null,
      checkoutReference: data.checkoutReference ? String(data.checkoutReference) : null,
      invoiceId: data.invoiceId ? String(data.invoiceId) : null,
      salesOrderId,
      salesOrderNumber,
      salesInvoiceId,
      conversionStatus,
      convertedAt: data.convertedAt ? String(data.convertedAt) : null,
      conversionErrorCode: data.conversionErrorCode ? String(data.conversionErrorCode) : null,
      idempotencyKey: String(data.idempotencyKey || ''),
      createdAt: String(data.createdAt || ''),
      updatedAt: String(data.updatedAt || ''),
      canCancel: cancelCheck.allowed,
    };
  }

  /**
   * 1. GET /api/v1/preorders/eligible-products
   * Queries products and strictly filters by `preorderactive === true` (Boolean).
   */
  async function listEligibleProducts(params: { limit?: number; cursor?: string }) {
    const limit = Math.min(Math.max(Number(params.limit) || 20, 1), 50);
    const snap = await adminDb.collection(COLLECTIONS.PRODUCTS).get();
    const eligibleDocs = snap.docs
      .map((doc: any) => ({ id: doc.id, data: doc.data() || {} }))
      .filter((entry: { id: string; data: Record<string, any> }) => isProductPreorderEligible(entry.data))
      .map((entry: { id: string; data: Record<string, any> }) => toEligibleProductDto(entry.id, entry.data))
      .sort((a: any, b: any) => a.name.localeCompare(b.name));

    let startIndex = 0;
    if (params.cursor) {
      const idx = eligibleDocs.findIndex((p: any) => p.id === params.cursor);
      if (idx >= 0) startIndex = idx + 1;
    }

    const page = eligibleDocs.slice(startIndex, startIndex + limit);
    const nextCursor =
      startIndex + limit < eligibleDocs.length ? page[page.length - 1]?.id ?? null : null;

    return {
      products: page,
      nextCursor,
      totalEligible: eligibleDocs.length,
    };
  }

  /**
   * 2. GET /api/v1/preorders/couriers
   * Returns the restricted preferred courier agent options:
   * Amazon Shipping, Delhivery, India Post, DTDC.
   */
  async function listCourierAgents(): Promise<{ courierAgents: string[] }> {
    return { courierAgents: [...config.defaultCourierAgents] };
  }

  /**
   * 3. POST /api/v1/preorders
   * Validates product eligibility (`preorderactive === true`), quantity, Full Amount vs Partial Payment
   * (10%–100% of Online Price * quantity), Gift Wrap, Special Suggestion, future Expected Date of Delivery,
   * and Preferred Courier Agent.
   *
   * By default (`persistImmediately !== true`), this endpoint ONLY validates the pre-order booking and
   * returns the authoritative `PreorderBookingDto` for the shopping cart WITHOUT adding records to
   * `preorders`, `preorder_idempotency`, or `preorder_events`.
   * Records in `preorders`, `preorder_idempotency`, and `preorder_events` are restricted to be created
   * ONLY after successful payment processing (`confirmPreorderPaymentsForCheckout`).
   */
  async function createPreorder(params: {
    userId: string;
    customerId?: string;
    customerDisplayName?: string;
    productId: string;
    quantity: number;
    paymentType: unknown;
    bookingAdvance?: unknown;
    giftWrap?: unknown;
    specialSuggestion?: unknown;
    expectedDeliveryDate: unknown;
    preferredCourierAgent: unknown;
    deliveryAddress?: unknown;
    shippingAddress?: unknown;
    idempotencyKey: string;
    persistImmediately?: boolean;
  }): Promise<{ booking: PreorderBookingDto; idempotentReplay: boolean }> {
    const { userId, productId, persistImmediately = false } = params;
    const quantity = Number(params.quantity);
    const rawIdemKey = String(params.idempotencyKey || '').trim();

    if (!isValidId(rawIdemKey) || rawIdemKey.length < 6) {
      throw new PreorderDomainError(
        'VALIDATION_ERROR',
        'A valid idempotencyKey (6–128 alphanumeric/hyphen/underscore chars) is required.',
        400
      );
    }
    if (!isValidId(productId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid productId.', 400);
    }
    if (!Number.isInteger(quantity) || quantity < config.minQuantity || quantity > config.maxQuantity) {
      throw new PreorderDomainError(
        'VALIDATION_ERROR',
        `Quantity must be an integer between ${config.minQuantity} and ${config.maxQuantity}.`,
        400
      );
    }

    const { paymentType, paymentTypeLabel } = normalizePaymentType(params.paymentType);
    const giftWrap = normalizeGiftWrap(params.giftWrap);
    const specialSuggestion = sanitizeNotes(params.specialSuggestion, config.maxSpecialSuggestionLength);
    const now = getNow();
    const expectedDeliveryDate = validateFutureDeliveryDate(
      params.expectedDeliveryDate,
      now,
      config.timezoneOffsetMinutes
    );
    const preferredCourierAgent = validatePreferredCourierAgent(
      params.preferredCourierAgent,
      config.defaultCourierAgents
    );
    const addrNorm = normalizeDeliveryAddress(params.deliveryAddress ?? params.shippingAddress);

    const idemDocId = `${userId}__${rawIdemKey}`;
    const idemRef = adminDb.collection(COLLECTIONS.IDEMPOTENCY).doc(idemDocId);
    const productRef = adminDb.collection(COLLECTIONS.PRODUCTS).doc(productId);

    return adminDb.runTransaction(async (tx: any) => {
      const [idemSnap, productSnap] = await Promise.all([tx.get(idemRef), tx.get(productRef)]);

      if (idemSnap.exists) {
        const existingPreorderId = String(idemSnap.data()?.preorderId || '');
        const existingRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(existingPreorderId);
        const existingSnap = await tx.get(existingRef);
        if (existingSnap.exists) {
          const existingData = existingSnap.data() || {};
          if (persistImmediately && addrNorm.deliveryAddress && !existingData.deliveryAddress) {
            const mergedExisting = {
              ...existingData,
              ...addrNorm,
              updatedAt: now.toISOString(),
            };
            tx.set(existingRef, mergedExisting, { merge: true });
            return {
              booking: toBookingDto(mergedExisting),
              idempotentReplay: true,
            };
          }
          return {
            booking: toBookingDto(existingData),
            idempotentReplay: true,
          };
        }
      }

      if (!productSnap.exists) {
        throw new PreorderDomainError('PRODUCT_NOT_FOUND', 'Product not found.', 404);
      }

      const productData = productSnap.data() || {};
      if (!isProductPreorderEligible(productData)) {
        throw new PreorderDomainError(
          'PRODUCT_NOT_PREORDERABLE',
          'This product is not eligible for pre-order booking.',
          403
        );
      }

      const pricing = computeAuthoritativePricing(productData, quantity);
      const advanceBreakdown = validateAndComputeAdvance({
        onlinePriceSnapshot: pricing.onlinePriceSnapshot,
        quantity,
        paymentType,
        rawBookingAdvance: params.bookingAdvance,
        config,
      });

      const nowIso = now.toISOString();
      const deterministicHash = crypto
        .createHash('sha256')
        .update(`${userId}__${rawIdemKey}`)
        .digest('hex')
        .slice(0, 24);
      const preorderId = `po_${deterministicHash}`;

      const imageUrl =
        productData.imageUrl ||
        productData.image ||
        (Array.isArray(productData.images) && productData.images.length > 0
          ? productData.images[0]
          : null) ||
        null;

      const bookingRecord = {
        preorderId,
        userId,
        customerId: String(params.customerId || userId),
        customerDisplayName: String(params.customerDisplayName || 'LeafyEarth Customer'),
        productId,
        productNameSnapshot: String(productData.name || ''),
        skuSnapshot: String(productData.sku || ''),
        packingSizeSnapshot: String(productData.packingSize || productData.unit || ''),
        imageUrlSnapshot: imageUrl ? String(imageUrl) : null,
        quantity,
        onlinePriceSnapshot: pricing.onlinePriceSnapshot,
        mrpSnapshot: pricing.mrpSnapshot,
        gstPercentageSnapshot: pricing.gstPercentageSnapshot,
        totalProductValue: advanceBreakdown.totalProductValue,
        paymentType,
        paymentTypeLabel,
        bookingAdvance: advanceBreakdown.bookingAdvance,
        remainingBalance: advanceBreakdown.remainingBalance,
        giftWrap,
        specialSuggestion,
        expectedDeliveryDate,
        preferredCourierAgent,
        ...addrNorm,
        currency: config.currency,
        bookingStatus: 'pending_payment' as PreorderBookingStatus,
        status: 'pending_payment' as PreorderBookingStatus,
        paymentStatus: 'unpaid' as PreorderPaymentStatus,
        paymentReference: null,
        checkoutReference: null,
        invoiceId: null,
        idempotencyKey: rawIdemKey,
        createdAt: nowIso,
        updatedAt: nowIso,
      };

      if (persistImmediately) {
        const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);
        const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
        const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);

        tx.set(preorderRef, bookingRecord);
        tx.set(idemRef, {
          preorderId,
          userId,
          idempotencyKey: rawIdemKey,
          createdAt: nowIso,
        });
        tx.set(eventRef, {
          eventId,
          preorderId,
          actorId: userId,
          actorRole: 'customer',
          eventType: 'preorder.booking_created',
          oldStatus: null,
          newStatus: 'pending_payment',
          paymentType,
          bookingAdvance: advanceBreakdown.bookingAdvance,
          remainingBalance: advanceBreakdown.remainingBalance,
          totalProductValue: advanceBreakdown.totalProductValue,
          quantity,
          deliveryAddress: addrNorm.deliveryAddress,
          occurredAt: nowIso,
        });
      }

      return {
        booking: toBookingDto(bookingRecord),
        idempotentReplay: false,
      };
    });
  }

  /**
   * 3b. PATCH /api/v1/preorders/:id (and POST /api/v1/preorders/:id/update)
   * Updates pre-order booking fields in `preorders/{preorderId}` including deliveryAddress / shippingAddress
   * for future reference, as well as quantity, bookingAdvance, preferredCourierAgent, expectedDeliveryDate,
   * specialSuggestion, or giftWrap.
   */
  async function updatePreorderDetails(params: {
    preorderId: string;
    requesterUid: string;
    isAdmin?: boolean;
    deliveryAddress?: unknown;
    shippingAddress?: unknown;
    quantity?: unknown;
    paymentType?: unknown;
    bookingAdvance?: unknown;
    giftWrap?: unknown;
    specialSuggestion?: unknown;
    expectedDeliveryDate?: unknown;
    preferredCourierAgent?: unknown;
  }): Promise<PreorderBookingDto> {
    const { preorderId, requesterUid, isAdmin = false } = params;
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }

    const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);

    return adminDb.runTransaction(async (tx: any) => {
      const snap = await tx.get(preorderRef);
      if (!snap.exists) {
        throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
      }

      const data = snap.data() || {};
      if (!isAdmin && data.userId !== requesterUid && data.customerId !== requesterUid) {
        throw new PreorderDomainError(
          'FORBIDDEN',
          'You do not have permission to update this pre-order booking.',
          403
        );
      }

      const baseDto = toBookingDto(data);
      const now = getNow();
      const nowIso = now.toISOString();

      let nextQty = baseDto.quantity;
      if (params.quantity !== undefined && params.quantity !== null) {
        const parsedQty = Number(params.quantity);
        if (
          !Number.isInteger(parsedQty) ||
          parsedQty < config.minQuantity ||
          parsedQty > config.maxQuantity
        ) {
          throw new PreorderDomainError(
            'VALIDATION_ERROR',
            `Quantity must be an integer between ${config.minQuantity} and ${config.maxQuantity}.`,
            400
          );
        }
        nextQty = parsedQty;
      }

      const { paymentType, paymentTypeLabel } =
        params.paymentType !== undefined && params.paymentType !== null
          ? normalizePaymentType(params.paymentType)
          : { paymentType: baseDto.paymentType, paymentTypeLabel: baseDto.paymentTypeLabel };

      const isAlreadyPaidOrPartiallyPaid =
        baseDto.paymentStatus === 'paid' || baseDto.paymentStatus === 'partially_paid';

      let totalProductValue = baseDto.totalProductValue;
      let bookingAdvance = baseDto.bookingAdvance;
      let remainingBalance = baseDto.remainingBalance;

      if (
        !isAlreadyPaidOrPartiallyPaid &&
        (nextQty !== baseDto.quantity ||
          params.bookingAdvance !== undefined ||
          params.paymentType !== undefined)
      ) {
        const advanceCalc = validateAndComputeAdvance({
          onlinePriceSnapshot: baseDto.onlinePriceSnapshot,
          quantity: nextQty,
          paymentType,
          rawBookingAdvance:
            paymentType === 'full'
              ? undefined
              : params.bookingAdvance !== undefined
              ? params.bookingAdvance
              : (baseDto.bookingAdvance / Math.max(1, baseDto.quantity)) * nextQty,
          config,
        });
        totalProductValue = advanceCalc.totalProductValue;
        bookingAdvance = advanceCalc.bookingAdvance;
        remainingBalance = advanceCalc.remainingBalance;
      }

      const giftWrap =
        params.giftWrap !== undefined ? normalizeGiftWrap(params.giftWrap) : baseDto.giftWrap;
      const specialSuggestion =
        params.specialSuggestion !== undefined
          ? sanitizeNotes(params.specialSuggestion, config.maxSpecialSuggestionLength)
          : baseDto.specialSuggestion;
      const expectedDeliveryDate =
        params.expectedDeliveryDate !== undefined && params.expectedDeliveryDate !== null
          ? validateFutureDeliveryDate(
              params.expectedDeliveryDate,
              now,
              config.timezoneOffsetMinutes
            )
          : baseDto.expectedDeliveryDate;
      const preferredCourierAgent =
        params.preferredCourierAgent !== undefined && params.preferredCourierAgent !== null
          ? validatePreferredCourierAgent(
              params.preferredCourierAgent,
              config.defaultCourierAgents
            )
          : baseDto.preferredCourierAgent;

      const rawAddressInput = params.deliveryAddress ?? params.shippingAddress;
      const addrNorm =
        rawAddressInput !== undefined
          ? normalizeDeliveryAddress(rawAddressInput)
          : normalizeDeliveryAddress(data.deliveryAddress ?? data.shippingAddress ?? data);

      const updatedRecord = {
        ...data,
        quantity: nextQty,
        totalProductValue,
        paymentType,
        paymentTypeLabel,
        bookingAdvance,
        remainingBalance,
        giftWrap,
        specialSuggestion,
        expectedDeliveryDate,
        preferredCourierAgent,
        ...addrNorm,
        updatedAt: nowIso,
      };

      tx.set(preorderRef, updatedRecord, { merge: true });

      const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
      const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
      tx.set(eventRef, {
        eventId,
        preorderId,
        actorId: requesterUid,
        actorRole: isAdmin ? 'admin' : 'customer',
        eventType: 'preorder.updated',
        quantity: nextQty,
        bookingAdvance,
        remainingBalance,
        preferredCourierAgent,
        deliveryAddress: addrNorm.deliveryAddress,
        occurredAt: nowIso,
      });

      return toBookingDto(updatedRecord);
    });
  }

  /**
   * 3c. Shared Idempotent Pre-Order -> Normal Sales Order Conversion Service (Sections 3, 4, 6, 7, 8, 10).
   *
   * Unified Server-Side Business Rule:
   *   outstandingBalance = max(0, roundMoney(authoritativeTotalProductValue - netVerifiedPaymentsAllocatedToPreorder))
   *   Eligible ONLY IF:
   *     - authoritativeTotalProductValue > 0
   *     - netVerifiedPaid >= authoritativeTotalProductValue && outstandingBalance === 0
   *     - paymentStatus === 'paid'
   *     - bookingStatus !== 'cancelled'
   *
   * Creates a canonical `sales_orders` record with `deliveryStatus = "PRE-ORDER"`,
   * deducts product stock in `products/{productId}`, writes conversion idempotency lock
   * `preorder_idempotency/conv__{preorderId}`, appends `preorder_events`, and invokes
   * `deps.onSalesOrderCreated` for downstream invoice & referral commission generation.
   */
  async function convertFullyPaidPreorderToSalesOrder(params: {
    preorderId: string;
    actorId?: string;
    actorRole?: 'system' | 'admin' | 'customer';
    note?: string;
  }): Promise<{
    converted: boolean;
    idempotentReplay: boolean;
    reason?: string;
    booking: PreorderBookingDto;
    salesOrderId: string | null;
    salesOrderNumber: string | null;
    salesOrder: Record<string, any> | null;
  }> {
    const preorderId = String(params.preorderId || '').trim();
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }

    const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);
    const convIdemRef = adminDb.collection(COLLECTIONS.IDEMPOTENCY).doc(`conv__${preorderId}`);

    let txOutcome: {
      converted: boolean;
      idempotentReplay: boolean;
      needsDownstreamHook: boolean;
      reason?: string;
      bookingRecord: Record<string, any>;
      salesOrderId: string | null;
      salesOrderNumber: string | null;
      salesOrder: Record<string, any> | null;
    };

    try {
      txOutcome = await adminDb.runTransaction(async (tx: any) => {
        const [preorderSnap, convIdemSnap] = await Promise.all([
          tx.get(preorderRef),
          tx.get(convIdemRef),
        ]);

        if (!preorderSnap.exists) {
          throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
        }

        const data = preorderSnap.data() || {};
        const deterministicSalesOrderId = data.salesOrderId
          ? String(data.salesOrderId)
          : `SO-PO-${preorderId}`;
        const deterministicSalesOrderNumber = data.salesOrderNumber
          ? String(data.salesOrderNumber)
          : `SO-2026-PO-${preorderId.replace(/^po_/, '').slice(0, 6).toUpperCase()}`;

        const salesOrderRef = adminDb
          .collection(COLLECTIONS.SALES_ORDERS)
          .doc(deterministicSalesOrderId);
        const productId = String(data.productId || '').trim();
        const productRef = productId
          ? adminDb.collection(COLLECTIONS.PRODUCTS).doc(productId)
          : null;

        const [salesOrderSnap, productSnap] = await Promise.all([
          tx.get(salesOrderRef),
          productRef ? tx.get(productRef) : Promise.resolve({ exists: false, data: () => ({}) }),
        ]);

        const nowIso = getNow().toISOString();

        // 1. Idempotency check: if sales_orders doc already exists or conversion lock exists
        if (
          salesOrderSnap.exists ||
          convIdemSnap.exists ||
          (data.conversionStatus === 'converted' && data.salesOrderId)
        ) {
          const existingSalesOrder = salesOrderSnap.exists ? salesOrderSnap.data() || null : null;
          const wasFailedDownstream = data.conversionStatus === 'failed';
          const linkedRecord = {
            ...data,
            salesOrderId: deterministicSalesOrderId,
            salesOrderNumber:
              existingSalesOrder?.orderNumber || deterministicSalesOrderNumber,
            conversionStatus: 'converted' as PreorderConversionStatus,
            convertedAt: data.convertedAt || nowIso,
            conversionErrorCode: null,
            updatedAt: data.updatedAt || nowIso,
          };

          if (
            data.conversionStatus !== 'converted' ||
            data.salesOrderId !== deterministicSalesOrderId
          ) {
            tx.set(preorderRef, linkedRecord, { merge: true });
          }

          return {
            converted: true,
            idempotentReplay: !wasFailedDownstream,
            needsDownstreamHook: Boolean(
              deps.onSalesOrderCreated &&
                existingSalesOrder &&
                (!linkedRecord.salesInvoiceId || wasFailedDownstream)
            ),
            bookingRecord: linkedRecord,
            salesOrderId: deterministicSalesOrderId,
            salesOrderNumber: linkedRecord.salesOrderNumber,
            salesOrder: existingSalesOrder,
          };
        }

        // 2. Unified Server-Side Eligibility Check (Section 3)
        const rawBookingStatus = String(
          data.bookingStatus || data.status || 'pending_payment'
        ) as PreorderBookingStatus;
        const rawPaymentStatus = String(data.paymentStatus || 'unpaid') as PreorderPaymentStatus;
        const onlinePriceSnapshot = roundMoney(
          Number(data.onlinePriceSnapshot ?? data.unitPriceSnapshot ?? 0)
        );
        const quantity = Math.max(1, Number(data.quantity || 1));
        const authoritativeTotal = roundMoney(
          Number(data.totalProductValue ?? onlinePriceSnapshot * quantity)
        );
        const verifiedPaid = roundMoney(
          data.totalVerifiedPaid !== undefined && data.totalVerifiedPaid !== null
            ? Number(data.totalVerifiedPaid)
            : rawPaymentStatus === 'paid'
            ? Number(data.bookingAdvance ?? authoritativeTotal)
            : rawPaymentStatus === 'partially_paid'
            ? Number(data.bookingAdvance ?? 0)
            : 0
        );
        const outstandingBalance = roundMoney(Math.max(0, authoritativeTotal - verifiedPaid));

        const isEligible =
          rawBookingStatus !== 'cancelled' &&
          rawPaymentStatus === 'paid' &&
          authoritativeTotal > 0 &&
          verifiedPaid >= authoritativeTotal - 0.001 &&
          outstandingBalance === 0;

        if (!isEligible) {
          return {
            converted: false,
            idempotentReplay: false,
            needsDownstreamHook: false,
            reason:
              rawBookingStatus === 'cancelled'
                ? 'Cannot convert a cancelled pre-order booking.'
                : `Pre-order booking has an outstanding balance of ₹${outstandingBalance.toFixed(
                    2
                  )} (paymentStatus: ${rawPaymentStatus}). Only fully paid bookings can be converted to sales orders.`,
            bookingRecord: data,
            salesOrderId: null,
            salesOrderNumber: null,
            salesOrder: null,
          };
        }

        // 3. Build canonical `sales_orders` record with `deliveryStatus = "PRE-ORDER"`
        const productData = productSnap.exists ? productSnap.data() || {} : {};
        const gstRate = roundMoney(
          Number(data.gstPercentageSnapshot ?? productData.gstPercentage ?? 18)
        );
        const hsnCode = String(productData.hsnCode || productData.hsn || '1234').trim();
        const gstInclusiveAmount = authoritativeTotal;
        const taxableValue =
          gstRate > 0
            ? roundMoney(gstInclusiveAmount / (1 + gstRate / 100))
            : gstInclusiveAmount;
        const gstAmount = roundMoney(gstInclusiveAmount - taxableValue);
        const hsnGstSummary = [
          {
            hsnCode,
            gstRate,
            taxableValue,
            gstAmount,
            totalAmount: gstInclusiveAmount,
          },
        ];

        const addrNorm = normalizeDeliveryAddress(
          data.deliveryAddress ?? data.shippingAddress ?? data
        );

        const convertedLineItem = {
          id: productId,
          productId,
          productName: String(data.productNameSnapshot || productData.name || ''),
          name: String(data.productNameSnapshot || productData.name || ''),
          sku: String(data.skuSnapshot || productData.sku || ''),
          packingSize: String(
            data.packingSizeSnapshot || productData.packingSize || productData.unit || ''
          ),
          unit: String(productData.unit || data.packingSizeSnapshot || ''),
          brandOwner: String(productData.brandOwner || productData.brandOwnerName || ''),
          imageUrl:
            data.imageUrlSnapshot || productData.imageUrl || productData.image || '',
          quantity,
          price: onlinePriceSnapshot,
          unitPrice: onlinePriceSnapshot,
          mrp: roundMoney(
            Number(data.mrpSnapshot || productData.mrp || onlinePriceSnapshot)
          ),
          gstPercentage: gstRate,
          hsnCode,
          taxableValue,
          gstAmount,
          gstInclusiveAmount,
          lineTotal: gstInclusiveAmount,
          isPreorder: false,
          convertedFromPreorderId: preorderId,
          giftWrap: Boolean(data.giftWrap),
          specialSuggestion: String(data.specialSuggestion || ''),
          expectedDeliveryDate: String(data.expectedDeliveryDate || ''),
          preferredCourierAgent: String(data.preferredCourierAgent || 'India Post'),
        };

        const salesOrderRecord: Record<string, any> = {
          id: deterministicSalesOrderId,
          orderNumber: deterministicSalesOrderNumber,
          preorderId,
          isConvertedPreorder: true,
          customerId: String(data.customerId || data.userId || ''),
          userId: String(data.userId || ''),
          customerName: String(
            addrNorm.deliveryAddressName ||
              data.customerDisplayName ||
              'LeafyEarth Customer'
          ),
          customerMobile: String(addrNorm.deliveryAddressMobile || ''),
          customerEmail: String(addrNorm.deliveryAddressEmail || ''),
          shippingAddress: addrNorm.shippingAddress,
          deliveryAddress: addrNorm.deliveryAddress,
          products: [convertedLineItem],
          totalTaxableValue: taxableValue,
          totalGstAmount: gstAmount,
          hsnGstSummary,
          gstByHsn: hsnGstSummary,
          deliveryFee: 0,
          discount: 0,
          totalValue: authoritativeTotal,
          grandTotal: authoritativeTotal,
          paymentMethod: 'Razorpay',
          paymentStatus: 'Paid',
          orderStatus: 'Confirmed',
          deliveryStatus: 'PRE-ORDER',
          preferredCourierAgent: String(data.preferredCourierAgent || 'India Post'),
          expectedDeliveryDate: String(data.expectedDeliveryDate || ''),
          giftWrap: Boolean(data.giftWrap),
          specialSuggestion: String(data.specialSuggestion || ''),
          paymentReference: String(
            data.lastPaymentReference ||
              data.balancePaymentReference ||
              data.paymentReference ||
              ''
          ),
          checkoutReference: String(
            data.balanceCheckoutReference || data.checkoutReference || ''
          ),
          initialBookingAdvance: roundMoney(
            Number(data.initialBookingAdvance ?? data.bookingAdvance ?? authoritativeTotal)
          ),
          totalVerifiedPaid: verifiedPaid,
          createdAt: nowIso,
          updatedAt: nowIso,
        };

        // 4. Deduct inventory stock in `products/{productId}` if product exists
        if (productSnap.exists && productRef) {
          const currentStock = Number(
            productData.stock ?? productData.availableStock ?? 0
          );
          const currentUnitsSold = Number(productData.unitsSold ?? 0);
          const currentRevenue = Number(productData.revenue ?? 0);
          tx.set(
            productRef,
            {
              ...productData,
              stock: Math.max(0, currentStock - quantity),
              unitsSold: currentUnitsSold + quantity,
              revenue: roundMoney(currentRevenue + authoritativeTotal),
              updatedAt: nowIso,
            },
            { merge: true }
          );
        }

        // 5. Persist `sales_orders/{salesOrderId}`, conversion idempotency lock, updated `preorders/{preorderId}`, and audit event
        tx.set(salesOrderRef, salesOrderRecord);
        tx.set(convIdemRef, {
          preorderId,
          salesOrderId: deterministicSalesOrderId,
          salesOrderNumber: deterministicSalesOrderNumber,
          userId: String(data.userId || ''),
          convertedAt: nowIso,
        });

        const convertedBookingRecord: Record<string, any> = {
          ...data,
          paymentStatus: 'paid' as PreorderPaymentStatus,
          totalVerifiedPaid: verifiedPaid,
          bookingAdvance: verifiedPaid,
          remainingBalance: 0,
          salesOrderId: deterministicSalesOrderId,
          salesOrderNumber: deterministicSalesOrderNumber,
          conversionStatus: 'converted' as PreorderConversionStatus,
          convertedAt: nowIso,
          conversionErrorCode: null,
          updatedAt: nowIso,
        };
        tx.set(preorderRef, convertedBookingRecord, { merge: true });

        const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
        const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
        tx.set(eventRef, {
          eventId,
          preorderId,
          salesOrderId: deterministicSalesOrderId,
          salesOrderNumber: deterministicSalesOrderNumber,
          actorId: params.actorId || String(data.userId || 'system'),
          actorRole: params.actorRole || 'system',
          eventType: 'preorder.converted_to_sales_order',
          oldStatus: rawBookingStatus,
          newStatus: convertedBookingRecord.bookingStatus || rawBookingStatus,
          paymentStatus: 'paid',
          conversionStatus: 'converted',
          deliveryStatus: 'PRE-ORDER',
          totalProductValue: authoritativeTotal,
          totalVerifiedPaid: verifiedPaid,
          remainingBalance: 0,
          note: sanitizeNotes(params.note, 300),
          occurredAt: nowIso,
        });

        return {
          converted: true,
          idempotentReplay: false,
          needsDownstreamHook: Boolean(deps.onSalesOrderCreated),
          bookingRecord: convertedBookingRecord,
          salesOrderId: deterministicSalesOrderId,
          salesOrderNumber: deterministicSalesOrderNumber,
          salesOrder: salesOrderRecord,
        };
      });
    } catch (err: any) {
      if (err instanceof PreorderDomainError) {
        throw err;
      }
      // Record recoverable conversion failure on `preorders` and `preorder_events`
      const nowIso = getNow().toISOString();
      const errorCode = String(err?.code || err?.message || 'CONVERSION_ERROR').slice(0, 120);
      try {
        await adminDb.runTransaction(async (tx: any) => {
          const snap = await tx.get(preorderRef);
          if (!snap.exists) return;
          tx.set(
            preorderRef,
            {
              conversionStatus: 'failed' as PreorderConversionStatus,
              conversionErrorCode: errorCode,
              updatedAt: nowIso,
            },
            { merge: true }
          );
          const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
          const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
          tx.set(eventRef, {
            eventId,
            preorderId,
            actorId: params.actorId || 'system',
            actorRole: params.actorRole || 'system',
            eventType: 'preorder.conversion_failed',
            conversionStatus: 'failed',
            conversionErrorCode: errorCode,
            occurredAt: nowIso,
          });
        });
      } catch (_) {}
      throw err;
    }

    // 6. Execute downstream sales transaction hook (tax invoice & referral commissions)
    if (txOutcome.converted && txOutcome.needsDownstreamHook && txOutcome.salesOrder && deps.onSalesOrderCreated) {
      try {
        const hookRes = await deps.onSalesOrderCreated(txOutcome.salesOrder);
        if (hookRes && hookRes.invoiceId) {
          const nowIso = getNow().toISOString();
          txOutcome.bookingRecord = {
            ...txOutcome.bookingRecord,
            salesInvoiceId: String(hookRes.invoiceId),
            conversionStatus: 'converted' as PreorderConversionStatus,
            conversionErrorCode: null,
            updatedAt: nowIso,
          };
          await adminDb.runTransaction(async (tx: any) => {
            tx.set(
              preorderRef,
              {
                salesInvoiceId: String(hookRes.invoiceId),
                conversionStatus: 'converted' as PreorderConversionStatus,
                conversionErrorCode: null,
                updatedAt: nowIso,
              },
              { merge: true }
            );
          });
        }
      } catch (hookErr: any) {
        const nowIso = getNow().toISOString();
        const errorCode = String(
          hookErr?.code || hookErr?.message || 'DOWNSTREAM_SALES_HOOK_FAILED'
        ).slice(0, 120);
        txOutcome.bookingRecord = {
          ...txOutcome.bookingRecord,
          conversionStatus: 'failed' as PreorderConversionStatus,
          conversionErrorCode: errorCode,
          updatedAt: nowIso,
        };
        await adminDb.runTransaction(async (tx: any) => {
          tx.set(
            preorderRef,
            {
              conversionStatus: 'failed' as PreorderConversionStatus,
              conversionErrorCode: errorCode,
              updatedAt: nowIso,
            },
            { merge: true }
          );
          const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
          const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
          tx.set(eventRef, {
            eventId,
            preorderId,
            salesOrderId: txOutcome.salesOrderId,
            actorId: params.actorId || 'system',
            actorRole: params.actorRole || 'system',
            eventType: 'preorder.conversion_failed',
            conversionStatus: 'failed',
            conversionErrorCode: errorCode,
            occurredAt: nowIso,
          });
        });
      }
    }

    return {
      converted: txOutcome.converted,
      idempotentReplay: txOutcome.idempotentReplay,
      reason: txOutcome.reason,
      booking: toBookingDto(txOutcome.bookingRecord),
      salesOrderId: txOutcome.salesOrderId,
      salesOrderNumber: txOutcome.salesOrderNumber,
      salesOrder: txOutcome.salesOrder,
    };
  }

  /**
   * 4. Confirm Pre-Order Payments on Verified Checkout Payment (Sections 3, 4, 5, 6, 8.3 & 12).
   * - Idempotent: repeated calls with the same `checkoutReference` return existing allocation without double-counting.
   * - Creates or updates each `preorders/{preorderId}` ONLY after successful payment verification:
   *     - `bookingStatus = 'confirmed'`
   *     - `paymentStatus = 'paid'` (when `remainingBalance === 0` and `totalVerifiedPaid >= totalProductValue`)
   *     - `paymentStatus = 'partially_paid'` (when `remainingBalance > 0`)
   *     - `paymentReference`, `checkoutReference`, `invoiceId`, and `deliveryAddress`
   * - Writes `preorder_idempotency` and `preorder_events` ONLY after successful payment verification.
   * - Writes `payment_allocations/{checkoutReference}`.
   * - Automatically invokes `convertFullyPaidPreorderToSalesOrder` for any booking that is now
   *   fully paid (`paymentStatus === 'paid' && remainingBalance === 0`), creating the normal
   *   `sales_orders` record with `deliveryStatus = "PRE-ORDER"`. Partially paid bookings remain
   *   exclusively in `preorders`.
   */
  async function confirmPreorderPaymentsForCheckout(params: {
    checkoutReference: string;
    paymentReference: string;
    userId: string;
    customerId?: string;
    customerDisplayName?: string;
    regularSalesOrderId?: string | null;
    regularSalesAmount: number;
    preorderIds: string[];
    deliveryAddress?: unknown;
    shippingAddress?: unknown;
    preorderItemOverrides?: Array<{
      preorderId?: string;
      productId?: string;
      productName?: string;
      quantity?: number;
      paymentType?: unknown;
      bookingAdvance?: number;
      giftWrap?: unknown;
      specialSuggestion?: unknown;
      expectedDeliveryDate?: unknown;
      preferredCourierAgent?: unknown;
      idempotencyKey?: string;
      customerId?: string;
      customerDisplayName?: string;
      isBalancePayment?: boolean;
      deliveryAddress?: unknown;
      shippingAddress?: unknown;
    }>;
    invoiceId?: string | null;
  }): Promise<{
    allocation: PaymentAllocationDto;
    bookings: PreorderBookingDto[];
    idempotentReplay: boolean;
  }> {
    const checkoutReference = String(params.checkoutReference || '').trim();
    const paymentReference = String(params.paymentReference || checkoutReference).trim();
    const userId = String(params.userId || '').trim();
    const regularSalesAmount = roundMoney(Math.max(0, Number(params.regularSalesAmount || 0)));
    const uniquePreorderIds = Array.from(
      new Set((params.preorderIds || []).map((id) => String(id || '').trim()).filter(Boolean))
    );

    if (!checkoutReference) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'checkoutReference is required.', 400);
    }
    if (uniquePreorderIds.length === 0) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'At least one preorderId is required.', 400);
    }

    const allocRef = adminDb.collection(COLLECTIONS.PAYMENT_ALLOCATIONS).doc(checkoutReference);

    const txResult = await adminDb.runTransaction(async (tx: any) => {
      const allocSnap = await tx.get(allocRef);
      const preorderRefs = uniquePreorderIds.map((id) =>
        adminDb.collection(COLLECTIONS.PREORDERS).doc(id)
      );
      const preorderSnaps = await Promise.all(preorderRefs.map((ref) => tx.get(ref)));

      if (allocSnap.exists && allocSnap.data()?.paymentStatus === 'paid') {
        const existingBookings = preorderSnaps
          .filter((s) => s.exists)
          .map((s) => toBookingDto(s.data() || {}));
        return {
          allocation: allocSnap.data() as PaymentAllocationDto,
          bookings: existingBookings,
          idempotentReplay: true,
        };
      }

      // Pre-read products for any pre-order items that have not been written to `preorders` yet
      // (since pre-order records are restricted to be created only after successful payment).
      const productSnapsByIndex: Record<number, any> = {};
      for (let i = 0; i < uniquePreorderIds.length; i++) {
        if (!preorderSnaps[i].exists) {
          const preorderId = uniquePreorderIds[i];
          const override =
            (params.preorderItemOverrides || []).find(
              (o) => String(o.preorderId || '') === preorderId
            ) || (params.preorderItemOverrides || [])[i];
          const productId = String(override?.productId || '').trim();
          if (productId) {
            const productRef = adminDb.collection(COLLECTIONS.PRODUCTS).doc(productId);
            productSnapsByIndex[i] = await tx.get(productRef);
          }
        }
      }

      const now = getNow();
      const nowIso = now.toISOString();
      const allocations: PreorderPaymentAllocationItemDto[] = [];
      const updatedBookings: PreorderBookingDto[] = [];
      let totalPreorderAdvance = 0;

      for (let i = 0; i < uniquePreorderIds.length; i++) {
        const snap = preorderSnaps[i];
        const preorderId = uniquePreorderIds[i];
        const override =
          (params.preorderItemOverrides || []).find(
            (o) => String(o.preorderId || '') === preorderId
          ) || (params.preorderItemOverrides || [])[i];

        if (!snap.exists) {
          const productSnap = productSnapsByIndex[i];
          if (!override || !override.productId || !productSnap || !productSnap.exists) {
            throw new PreorderDomainError(
              'NOT_FOUND',
              `Pre-order booking '${preorderId}' not found.`,
              404
            );
          }

          const productData = productSnap.data() || {};
          if (!isProductPreorderEligible(productData)) {
            throw new PreorderDomainError(
              'PRODUCT_NOT_PREORDERABLE',
              'This product is not eligible for pre-order booking.',
              403
            );
          }

          const finalQty = Math.max(1, Number(override.quantity || 1));
          const pricing = computeAuthoritativePricing(productData, finalQty);
          const { paymentType, paymentTypeLabel } = normalizePaymentType(
            override.paymentType || 'full'
          );
          const advanceCalc = validateAndComputeAdvance({
            onlinePriceSnapshot: pricing.onlinePriceSnapshot,
            quantity: finalQty,
            paymentType,
            rawBookingAdvance: override.bookingAdvance,
            config,
          });
          const giftWrap = normalizeGiftWrap(override.giftWrap);
          const specialSuggestion = sanitizeNotes(
            override.specialSuggestion,
            config.maxSpecialSuggestionLength
          );
          const expectedDeliveryDate = validateFutureDeliveryDate(
            override.expectedDeliveryDate,
            now,
            config.timezoneOffsetMinutes
          );
          const preferredCourierAgent = validatePreferredCourierAgent(
            override.preferredCourierAgent || 'India Post',
            config.defaultCourierAgents
          );
          const candidateAddress =
            override.deliveryAddress ??
            override.shippingAddress ??
            params.deliveryAddress ??
            params.shippingAddress;
          const addrNorm = normalizeDeliveryAddress(candidateAddress);

          const isFullyPaid =
            advanceCalc.remainingBalance <= 0 &&
            advanceCalc.bookingAdvance >= advanceCalc.totalProductValue - 0.001;
          const nextPaymentStatus: PreorderPaymentStatus = isFullyPaid
            ? 'paid'
            : 'partially_paid';
          const nextConversionStatus: PreorderConversionStatus = isFullyPaid
            ? 'pending'
            : 'not_applicable';

          const rawIdemKey = String(
            override.idempotencyKey || `chk_${checkoutReference}_${preorderId}`
          ).trim();
          const idemDocId = `${userId}__${rawIdemKey}`;
          const idemRef = adminDb.collection(COLLECTIONS.IDEMPOTENCY).doc(idemDocId);

          const imageUrl =
            productData.imageUrl ||
            productData.image ||
            (Array.isArray(productData.images) && productData.images.length > 0
              ? productData.images[0]
              : null) ||
            null;

          const createdRecord = {
            preorderId,
            userId,
            customerId: String(override.customerId || params.customerId || userId),
            customerDisplayName: String(
              override.customerDisplayName ||
                params.customerDisplayName ||
                'LeafyEarth Customer'
            ),
            productId: String(override.productId),
            productNameSnapshot: String(productData.name || override.productName || ''),
            skuSnapshot: String(productData.sku || ''),
            packingSizeSnapshot: String(productData.packingSize || productData.unit || ''),
            imageUrlSnapshot: imageUrl ? String(imageUrl) : null,
            quantity: finalQty,
            onlinePriceSnapshot: pricing.onlinePriceSnapshot,
            mrpSnapshot: pricing.mrpSnapshot,
            gstPercentageSnapshot: pricing.gstPercentageSnapshot,
            totalProductValue: advanceCalc.totalProductValue,
            paymentType,
            paymentTypeLabel,
            bookingAdvance: advanceCalc.bookingAdvance,
            initialBookingAdvance: advanceCalc.bookingAdvance,
            totalVerifiedPaid: advanceCalc.bookingAdvance,
            remainingBalance: advanceCalc.remainingBalance,
            giftWrap,
            specialSuggestion,
            expectedDeliveryDate,
            preferredCourierAgent,
            ...addrNorm,
            currency: config.currency,
            bookingStatus: 'confirmed' as PreorderBookingStatus,
            status: 'confirmed' as PreorderBookingStatus,
            paymentStatus: nextPaymentStatus,
            paymentReference,
            lastPaymentReference: paymentReference,
            checkoutReference,
            invoiceId: params.invoiceId || checkoutReference,
            salesOrderId: null,
            salesOrderNumber: null,
            salesInvoiceId: null,
            conversionStatus: nextConversionStatus,
            convertedAt: null,
            conversionErrorCode: null,
            idempotencyKey: rawIdemKey,
            createdAt: nowIso,
            updatedAt: nowIso,
          };

          const dto = toBookingDto(createdRecord);

          // Write to `preorders`, `preorder_idempotency`, and `preorder_events` ONLY now that payment succeeded
          tx.set(preorderRefs[i], createdRecord);
          tx.set(idemRef, {
            preorderId,
            userId,
            idempotencyKey: rawIdemKey,
            checkoutReference,
            paymentReference,
            createdAt: nowIso,
          });

          const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
          const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
          tx.set(eventRef, {
            eventId,
            preorderId,
            actorId: userId || dto.userId,
            actorRole: 'system',
            eventType: 'preorder.payment_confirmed',
            oldStatus: null,
            newStatus: 'confirmed',
            paymentStatus: nextPaymentStatus,
            conversionStatus: nextConversionStatus,
            paymentReference,
            checkoutReference,
            productId: dto.productId,
            productName: dto.productNameSnapshot,
            quantity: dto.quantity,
            paymentType: dto.paymentType,
            bookingAdvance: dto.bookingAdvance,
            initialBookingAdvance: dto.initialBookingAdvance,
            totalVerifiedPaid: dto.totalVerifiedPaid,
            remainingBalance: dto.remainingBalance,
            totalProductValue: dto.totalProductValue,
            expectedDeliveryDate: dto.expectedDeliveryDate,
            preferredCourierAgent: dto.preferredCourierAgent,
            deliveryAddress: addrNorm.deliveryAddress,
            occurredAt: nowIso,
          });

          totalPreorderAdvance = roundMoney(totalPreorderAdvance + dto.bookingAdvance);
          allocations.push({
            preorderId: dto.preorderId,
            productId: dto.productId,
            productName: dto.productNameSnapshot,
            quantity: dto.quantity,
            onlinePriceSnapshot: dto.onlinePriceSnapshot,
            totalProductValue: dto.totalProductValue,
            paymentType: dto.paymentType,
            paymentTypeLabel: dto.paymentTypeLabel,
            bookingAdvance: dto.bookingAdvance,
            remainingBalance: dto.remainingBalance,
            giftWrap: dto.giftWrap,
            specialSuggestion: dto.specialSuggestion,
            expectedDeliveryDate: dto.expectedDeliveryDate,
            preferredCourierAgent: dto.preferredCourierAgent,
          });
          updatedBookings.push(dto);
          continue;
        }

        const data = snap.data() || {};
        const baseDto = toBookingDto(data);
        const isBalancePayment = Boolean(override?.isBalancePayment);
        const finalQty =
          !isBalancePayment &&
          override?.quantity &&
          Number.isInteger(Number(override.quantity)) &&
          Number(override.quantity) >= 1
            ? Number(override.quantity)
            : baseDto.quantity;

        const previousVerifiedPaid = roundMoney(
          Number(
            data.totalVerifiedPaid ??
              data.initialBookingAdvance ??
              data.bookingAdvance ??
              0
          )
        );
        const preservedInitialAdvance = roundMoney(
          Number(data.initialBookingAdvance ?? data.bookingAdvance ?? previousVerifiedPaid)
        );

        const requestedBalancePayment =
          isBalancePayment &&
          override?.bookingAdvance !== undefined &&
          Number.isFinite(Number(override.bookingAdvance)) &&
          Number(override.bookingAdvance) > 0
            ? roundMoney(Number(override.bookingAdvance))
            : roundMoney(Math.max(0, baseDto.remainingBalance));

        const balancePaidAmount = isBalancePayment
          ? roundMoney(Math.min(baseDto.remainingBalance, requestedBalancePayment))
          : 0;

        const advanceCalc = isBalancePayment
          ? {
              totalProductValue: baseDto.totalProductValue,
              bookingAdvance: roundMoney(
                Math.min(baseDto.totalProductValue, previousVerifiedPaid + balancePaidAmount)
              ),
              remainingBalance: roundMoney(
                Math.max(
                  0,
                  baseDto.totalProductValue - (previousVerifiedPaid + balancePaidAmount)
                )
              ),
            }
          : validateAndComputeAdvance({
              onlinePriceSnapshot: baseDto.onlinePriceSnapshot,
              quantity: finalQty,
              paymentType: baseDto.paymentType,
              rawBookingAdvance:
                baseDto.paymentType === 'full'
                  ? undefined
                  : override?.bookingAdvance !== undefined
                  ? override.bookingAdvance
                  : baseDto.bookingAdvance,
              config,
            });

        const isFullySettled =
          advanceCalc.remainingBalance <= 0 &&
          advanceCalc.bookingAdvance >= advanceCalc.totalProductValue - 0.001;
        const nextPaymentStatus: PreorderPaymentStatus = isFullySettled
          ? 'paid'
          : 'partially_paid';
        const nextConversionStatus: PreorderConversionStatus = isFullySettled
          ? data.conversionStatus === 'converted'
            ? 'converted'
            : 'pending'
          : 'not_applicable';

        const candidateAddress =
          override?.deliveryAddress ??
          override?.shippingAddress ??
          params.deliveryAddress ??
          params.shippingAddress;
        const addrNorm =
          candidateAddress !== undefined
            ? normalizeDeliveryAddress(candidateAddress)
            : normalizeDeliveryAddress(data.deliveryAddress ?? data.shippingAddress ?? data);

        const rawIdemKey = String(
          data.idempotencyKey || override?.idempotencyKey || `chk_${checkoutReference}_${preorderId}`
        ).trim();
        const idemDocId = `${userId || baseDto.userId}__${rawIdemKey}`;
        const idemRef = adminDb.collection(COLLECTIONS.IDEMPOTENCY).doc(idemDocId);

        const updatedRecord = {
          ...data,
          quantity: finalQty,
          totalProductValue: advanceCalc.totalProductValue,
          bookingAdvance: advanceCalc.bookingAdvance,
          initialBookingAdvance: isBalancePayment
            ? preservedInitialAdvance
            : advanceCalc.bookingAdvance,
          totalVerifiedPaid: advanceCalc.bookingAdvance,
          remainingBalance: advanceCalc.remainingBalance,
          ...addrNorm,
          bookingStatus: (data.bookingStatus && data.bookingStatus !== 'pending_payment'
            ? data.bookingStatus
            : 'confirmed') as PreorderBookingStatus,
          status: (data.bookingStatus && data.bookingStatus !== 'pending_payment'
            ? data.bookingStatus
            : 'confirmed') as PreorderBookingStatus,
          paymentStatus: nextPaymentStatus,
          paymentReference: isBalancePayment
            ? data.paymentReference || paymentReference
            : paymentReference,
          lastPaymentReference: paymentReference,
          checkoutReference: data.checkoutReference || checkoutReference,
          ...(isBalancePayment
            ? {
                balancePaymentReference: paymentReference,
                balanceCheckoutReference: checkoutReference,
              }
            : {}),
          invoiceId: data.invoiceId || params.invoiceId || checkoutReference,
          conversionStatus: nextConversionStatus,
          idempotencyKey: rawIdemKey,
          updatedAt: nowIso,
        };
        const dto = toBookingDto(updatedRecord);

        tx.set(preorderRefs[i], updatedRecord, { merge: true });
        tx.set(
          idemRef,
          {
            preorderId,
            userId: userId || dto.userId,
            idempotencyKey: rawIdemKey,
            checkoutReference: updatedRecord.checkoutReference,
            paymentReference,
            createdAt: data.createdAt || nowIso,
          },
          { merge: true }
        );

        const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
        const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
        tx.set(eventRef, {
          eventId,
          preorderId,
          actorId: userId || dto.userId,
          actorRole: 'system',
          eventType: isBalancePayment
            ? 'preorder.balance_payment_confirmed'
            : 'preorder.payment_confirmed',
          oldStatus: dto.bookingStatus,
          newStatus: updatedRecord.bookingStatus,
          paymentStatus: nextPaymentStatus,
          conversionStatus: nextConversionStatus,
          paymentReference,
          checkoutReference,
          bookingAdvance: isBalancePayment ? balancePaidAmount : dto.bookingAdvance,
          initialBookingAdvance: dto.initialBookingAdvance,
          totalVerifiedPaid: dto.totalVerifiedPaid,
          remainingBalance: dto.remainingBalance,
          deliveryAddress: addrNorm.deliveryAddress,
          occurredAt: nowIso,
        });

        const txAllocatedAmount = isBalancePayment ? balancePaidAmount : dto.bookingAdvance;
        totalPreorderAdvance = roundMoney(totalPreorderAdvance + txAllocatedAmount);
        allocations.push({
          preorderId: dto.preorderId,
          productId: dto.productId,
          productName: dto.productNameSnapshot,
          quantity: dto.quantity,
          onlinePriceSnapshot: dto.onlinePriceSnapshot,
          totalProductValue: dto.totalProductValue,
          paymentType: dto.paymentType,
          paymentTypeLabel: dto.paymentTypeLabel,
          bookingAdvance: txAllocatedAmount,
          remainingBalance: dto.remainingBalance,
          giftWrap: dto.giftWrap,
          specialSuggestion: dto.specialSuggestion,
          expectedDeliveryDate: dto.expectedDeliveryDate,
          preferredCourierAgent: dto.preferredCourierAgent,
        });
        updatedBookings.push(toBookingDto(updatedRecord));
      }

      const customerGrandTotalPayable = roundMoney(regularSalesAmount + totalPreorderAdvance);
      const allocationRecord: PaymentAllocationDto = {
        checkoutReference,
        paymentReference,
        userId,
        regularSalesOrderId: params.regularSalesOrderId || null,
        regularSalesAmount,
        totalPreorderAdvance,
        customerGrandTotalPayable,
        paymentStatus: 'paid',
        preorderIds: uniquePreorderIds,
        allocations,
        createdAt: allocSnap.exists
          ? String(allocSnap.data()?.createdAt || nowIso)
          : nowIso,
        updatedAt: nowIso,
      };

      tx.set(allocRef, allocationRecord, { merge: true });

      return {
        allocation: allocationRecord,
        bookings: updatedBookings,
        idempotentReplay: false,
      };
    });

    // Automatically convert any fully paid pre-order booking to a normal sales order (`deliveryStatus = "PRE-ORDER"`).
    // Partially paid bookings (`paymentStatus === 'partially_paid'`, `remainingBalance > 0`) are never converted.
    const finalBookings: PreorderBookingDto[] = [];
    for (const booking of txResult.bookings) {
      if (
        booking.paymentStatus === 'paid' &&
        booking.remainingBalance <= 0 &&
        booking.totalVerifiedPaid >= booking.totalProductValue - 0.001 &&
        booking.conversionStatus !== 'converted'
      ) {
        const convRes = await convertFullyPaidPreorderToSalesOrder({
          preorderId: booking.preorderId,
          actorId: userId || booking.userId,
          actorRole: 'system',
        });
        finalBookings.push(convRes.booking);
      } else {
        finalBookings.push(booking);
      }
    }

    return {
      allocation: txResult.allocation,
      bookings: finalBookings,
      idempotentReplay: txResult.idempotentReplay,
    };
  }

  /**
   * 5. Record Failed / Cancelled Checkout Payment (Section 12).
   * - Restricted: NEVER writes or adds records to `preorders` or `preorder_idempotency` when payment
   *   generation or payment verification is cancelled or failed.
   * - Updates/writes the cancelled or failed payment details into `preorder_events`.
   */
  async function failPreorderPaymentsForCheckout(params: {
    checkoutReference: string;
    paymentReference?: string | null;
    userId: string;
    regularSalesAmount?: number;
    preorderIds?: string[];
    preorderItems?: Array<Record<string, any>>;
    outcome?: 'cancelled' | 'failed';
    reason?: string;
    deliveryAddress?: unknown;
    shippingAddress?: unknown;
  }): Promise<{ bookings: PreorderBookingDto[]; events: Array<Record<string, any>> }> {
    const checkoutReference = String(params.checkoutReference || '').trim();
    const rawItems = Array.isArray(params.preorderItems) ? params.preorderItems : [];
    const uniquePreorderIds = Array.from(
      new Set(
        [
          ...(params.preorderIds || []),
          ...rawItems.map((it) => it?.preorderId || it?.bookingReference),
        ]
          .map((id) => String(id || '').trim())
          .filter(Boolean)
      )
    );
    if (!checkoutReference || (uniquePreorderIds.length === 0 && rawItems.length === 0)) {
      return { bookings: [], events: [] };
    }

    const outcome: 'cancelled' | 'failed' =
      params.outcome === 'cancelled' ||
      String(params.reason || '')
        .toLowerCase()
        .includes('cancel')
        ? 'cancelled'
        : 'failed';
    const eventType =
      outcome === 'cancelled' ? 'preorder.payment_cancelled' : 'preorder.payment_failed';

    const allocRef = adminDb.collection(COLLECTIONS.PAYMENT_ALLOCATIONS).doc(checkoutReference);

    return adminDb.runTransaction(async (tx: any) => {
      const allocSnap = await tx.get(allocRef);
      const preorderRefs = uniquePreorderIds.map((id) =>
        adminDb.collection(COLLECTIONS.PREORDERS).doc(id)
      );
      const preorderSnaps =
        preorderRefs.length > 0
          ? await Promise.all(preorderRefs.map((ref) => tx.get(ref)))
          : [];

      // Never downgrade an already confirmed/paid checkout allocation
      if (allocSnap.exists && allocSnap.data()?.paymentStatus === 'paid') {
        return {
          bookings: preorderSnaps
            .filter((s) => s.exists)
            .map((s) => toBookingDto(s.data() || {})),
          events: [],
        };
      }

      const nowIso = getNow().toISOString();
      const existingBookings: PreorderBookingDto[] = [];
      const recordedEvents: Array<Record<string, any>> = [];
      let totalPreorderAdvance = 0;

      const addrNorm = normalizeDeliveryAddress(
        params.deliveryAddress ?? params.shippingAddress
      );

      const itemCount = Math.max(uniquePreorderIds.length, rawItems.length);
      for (let i = 0; i < itemCount; i++) {
        const preorderId =
          uniquePreorderIds[i] ||
          String(
            rawItems[i]?.preorderId ||
              rawItems[i]?.bookingReference ||
              `po_${checkoutReference}_${i + 1}`
          ).trim();
        const snap = preorderSnaps[i];
        const rawItem =
          rawItems.find(
            (it) => String(it?.preorderId || it?.bookingReference || '') === preorderId
          ) ||
          rawItems[i] ||
          {};

        let dto: PreorderBookingDto | null = null;
        if (snap && snap.exists) {
          dto = toBookingDto(snap.data() || {});
          existingBookings.push(dto);
        }

        const itemAdvance = roundMoney(
          Number(rawItem.bookingAdvance ?? dto?.bookingAdvance ?? 0)
        );
        const itemRemainingBalance = roundMoney(
          Number(rawItem.remainingBalance ?? dto?.remainingBalance ?? 0)
        );
        const itemTotalValue = roundMoney(
          Number(rawItem.totalProductValue ?? dto?.totalProductValue ?? 0)
        );
        const itemQty = Math.max(1, Number(rawItem.quantity ?? dto?.quantity ?? 1));
        const itemAddressNorm =
          rawItem.deliveryAddress || rawItem.shippingAddress
            ? normalizeDeliveryAddress(rawItem.deliveryAddress ?? rawItem.shippingAddress)
            : addrNorm;

        totalPreorderAdvance = roundMoney(totalPreorderAdvance + itemAdvance);

        const cleanRef = checkoutReference.replace(/[^a-zA-Z0-9_-]/g, '');
        const cleanPoId = preorderId.replace(/[^a-zA-Z0-9_-]/g, '');
        const eventId = `poe_${cleanRef}_${cleanPoId}`;
        const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
        const eventPayload = {
          eventId,
          preorderId,
          checkoutReference,
          paymentReference: params.paymentReference || null,
          actorId: params.userId,
          actorRole: 'customer',
          eventType,
          outcome,
          paymentStatus: outcome,
          bookingStatus: dto ? dto.bookingStatus : 'unconfirmed',
          reason: sanitizeNotes(
            params.reason ||
              (outcome === 'cancelled'
                ? 'Payment generation or checkout cancelled by user.'
                : 'Payment generation or verification failed.'),
            300
          ),
          productId: String(rawItem.productId || rawItem.id || dto?.productId || ''),
          productName: String(
            rawItem.productName || rawItem.name || dto?.productNameSnapshot || ''
          ),
          quantity: itemQty,
          paymentType: String(rawItem.paymentType || dto?.paymentType || 'full'),
          bookingAdvance: itemAdvance,
          remainingBalance: itemRemainingBalance,
          totalProductValue: itemTotalValue,
          giftWrap: Boolean(rawItem.giftWrap ?? dto?.giftWrap ?? false),
          specialSuggestion: sanitizeNotes(
            rawItem.specialSuggestion ?? dto?.specialSuggestion ?? '',
            config.maxSpecialSuggestionLength
          ),
          expectedDeliveryDate: String(
            rawItem.expectedDeliveryDate || dto?.expectedDeliveryDate || ''
          ),
          preferredCourierAgent: String(
            rawItem.preferredCourierAgent || dto?.preferredCourierAgent || ''
          ),
          deliveryAddress: itemAddressNorm.deliveryAddress ?? dto?.deliveryAddress ?? null,
          occurredAt: nowIso,
          updatedAt: nowIso,
        };

        tx.set(eventRef, eventPayload, { merge: true });
        recordedEvents.push(eventPayload);
      }

      const regularSalesAmount = roundMoney(Math.max(0, Number(params.regularSalesAmount || 0)));
      tx.set(
        allocRef,
        {
          checkoutReference,
          paymentReference: params.paymentReference || null,
          userId: params.userId,
          regularSalesOrderId: null,
          regularSalesAmount,
          totalPreorderAdvance,
          customerGrandTotalPayable: roundMoney(regularSalesAmount + totalPreorderAdvance),
          paymentStatus: 'failed' as PreorderPaymentStatus,
          outcome,
          preorderIds: uniquePreorderIds,
          failureReason: sanitizeNotes(params.reason, 300),
          createdAt: allocSnap.exists
            ? String(allocSnap.data()?.createdAt || nowIso)
            : nowIso,
          updatedAt: nowIso,
        },
        { merge: true }
      );

      return { bookings: existingBookings, events: recordedEvents };
    });
  }

  /**
   * 6. GET /api/v1/preorders/:id
   * Owner or authorized Admin only. Never leaks another user's booking.
   */
  async function getPreorderById(params: {
    preorderId: string;
    requesterUid: string;
    isAdmin: boolean;
  }) {
    const { preorderId, requesterUid, isAdmin } = params;
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }

    const snap = await adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId).get();
    if (!snap.exists) {
      throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
    }

    const data = snap.data() || {};
    if (!isAdmin && data.userId !== requesterUid) {
      throw new PreorderDomainError(
        'FORBIDDEN',
        'You do not have permission to view this pre-order.',
        403
      );
    }

    return toBookingDto(data);
  }

  /**
   * 7. GET /api/v1/preorders/mine
   * Paginated bookings for the authenticated user.
   */
  async function listMyPreorders(params: { userId: string; limit?: number; cursor?: string }) {
    const limit = Math.min(Math.max(Number(params.limit) || 20, 1), 50);
    const snap = await adminDb
      .collection(COLLECTIONS.PREORDERS)
      .where('userId', '==', params.userId)
      .get();

    const all = snap.docs
      .map((doc: any) => toBookingDto(doc.data() || {}))
      .sort((a: PreorderBookingDto, b: PreorderBookingDto) =>
        b.createdAt.localeCompare(a.createdAt)
      );

    let startIndex = 0;
    if (params.cursor) {
      const idx = all.findIndex((b: PreorderBookingDto) => b.preorderId === params.cursor);
      if (idx >= 0) startIndex = idx + 1;
    }

    const page = all.slice(startIndex, startIndex + limit);
    const nextCursor =
      startIndex + limit < all.length ? page[page.length - 1]?.preorderId ?? null : null;

    return {
      preorders: page,
      nextCursor,
    };
  }

  /**
   * 8. POST /api/v1/preorders/:id/cancel
   * Owner or Admin cancellation in a transaction; logs an audit event.
   */
  async function cancelPreorder(params: {
    preorderId: string;
    requesterUid: string;
    isAdmin: boolean;
    reason?: string;
  }): Promise<PreorderBookingDto> {
    const { preorderId, requesterUid, isAdmin } = params;
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }

    const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);

    return adminDb.runTransaction(async (tx: any) => {
      const snap = await tx.get(preorderRef);
      if (!snap.exists) {
        throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
      }

      const data = snap.data() || {};
      if (!isAdmin && data.userId !== requesterUid) {
        throw new PreorderDomainError(
          'FORBIDDEN',
          'You do not have permission to cancel this pre-order.',
          403
        );
      }

      const currentStatus = (data.bookingStatus || data.status || 'pending_payment') as PreorderBookingStatus;
      if (currentStatus === 'cancelled') {
        return toBookingDto(data);
      }

      if (!isAdmin) {
        const check = canCustomerCancelBooking({ bookingStatus: currentStatus });
        if (!check.allowed) {
          throw new PreorderDomainError(
            'CANCELLATION_NOT_ALLOWED',
            check.reason || 'Cancellation not permitted.',
            409
          );
        }
      } else if (!isValidStatusTransition(currentStatus, 'cancelled')) {
        throw new PreorderDomainError(
          'INVALID_STATUS_TRANSITION',
          `Cannot transition pre-order from '${currentStatus}' to 'cancelled'.`,
          409
        );
      }

      const nowIso = getNow().toISOString();
      const updatedData = {
        ...data,
        bookingStatus: 'cancelled' as PreorderBookingStatus,
        status: 'cancelled' as PreorderBookingStatus,
        cancelledAt: nowIso,
        cancelledBy: requesterUid,
        cancellationReason: sanitizeNotes(params.reason, 300),
        updatedAt: nowIso,
      };
      tx.set(preorderRef, updatedData, { merge: true });

      const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
      const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
      tx.set(eventRef, {
        eventId,
        preorderId,
        actorId: requesterUid,
        actorRole: isAdmin ? 'admin' : 'customer',
        eventType: 'preorder.cancelled',
        oldStatus: currentStatus,
        newStatus: 'cancelled',
        reason: sanitizeNotes(params.reason, 300),
        occurredAt: nowIso,
      });

      return toBookingDto(updatedData);
    });
  }

  /**
   * 9. PATCH /api/v1/admin/preorders/:id/status
   * Admin-only status update enforcing allowed transitions:
   * `pending_payment -> confirmed -> processing -> ready_for_dispatch -> dispatched -> delivered`.
   */
  async function adminUpdateStatus(params: {
    preorderId: string;
    adminUid: string;
    nextStatus: PreorderBookingStatus;
    note?: string;
  }): Promise<PreorderBookingDto> {
    const { preorderId, adminUid, nextStatus } = params;
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }
    if (!Object.keys(ALLOWED_STATUS_TRANSITIONS).includes(nextStatus)) {
      throw new PreorderDomainError('VALIDATION_ERROR', `Invalid status '${nextStatus}'.`, 400);
    }

    if (nextStatus === 'cancelled') {
      return cancelPreorder({
        preorderId,
        requesterUid: adminUid,
        isAdmin: true,
        reason: params.note,
      });
    }

    const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);
    return adminDb.runTransaction(async (tx: any) => {
      const snap = await tx.get(preorderRef);
      if (!snap.exists) {
        throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
      }

      const data = snap.data() || {};
      const currentStatus = (data.bookingStatus || data.status || 'pending_payment') as PreorderBookingStatus;
      if (!isValidStatusTransition(currentStatus, nextStatus)) {
        throw new PreorderDomainError(
          'INVALID_STATUS_TRANSITION',
          `Invalid status transition from '${currentStatus}' to '${nextStatus}'.`,
          409
        );
      }

      const nowIso = getNow().toISOString();
      const updatedData = {
        ...data,
        bookingStatus: nextStatus,
        status: nextStatus,
        updatedAt: nowIso,
      };
      tx.set(preorderRef, updatedData, { merge: true });

      const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
      const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
      tx.set(eventRef, {
        eventId,
        preorderId,
        actorId: adminUid,
        actorRole: 'admin',
        eventType: 'preorder.status_changed',
        oldStatus: currentStatus,
        newStatus: nextStatus,
        note: sanitizeNotes(params.note, 300),
        occurredAt: nowIso,
      });

      return toBookingDto(updatedData);
    });
  }

  /**
   * 10. GET /api/v1/preorders/:id/balance
   * Returns the authoritative server-side outstanding balance, cumulative verified paid amount,
   * payment status, conversion status, and linked sales order reference (Section 9).
   */
  async function getPreorderBalanceQuote(params: {
    preorderId: string;
    requesterUid: string;
    isAdmin: boolean;
  }) {
    const { preorderId, requesterUid, isAdmin } = params;
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }

    const snap = await adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId).get();
    if (!snap.exists) {
      throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
    }

    const data = snap.data() || {};
    if (!isAdmin && data.userId !== requesterUid && data.customerId !== requesterUid) {
      throw new PreorderDomainError(
        'FORBIDDEN',
        'You do not have permission to view this pre-order balance.',
        403
      );
    }

    const dto = toBookingDto(data);
    const authoritativeTotal = roundMoney(dto.onlinePriceSnapshot * dto.quantity);
    const verifiedPaid = roundMoney(dto.totalVerifiedPaid);
    const outstandingBalance = roundMoney(Math.max(0, authoritativeTotal - verifiedPaid));
    const canPayBalance =
      dto.bookingStatus !== 'cancelled' &&
      dto.paymentStatus === 'partially_paid' &&
      outstandingBalance > 0 &&
      dto.conversionStatus !== 'converted' &&
      !dto.salesOrderId;

    return {
      preorderId: dto.preorderId,
      productId: dto.productId,
      productName: dto.productNameSnapshot,
      quantity: dto.quantity,
      onlinePriceSnapshot: dto.onlinePriceSnapshot,
      totalProductValue: authoritativeTotal,
      initialBookingAdvance: dto.initialBookingAdvance,
      totalVerifiedPaid: verifiedPaid,
      remainingBalance: outstandingBalance,
      currency: dto.currency,
      paymentStatus: dto.paymentStatus,
      bookingStatus: dto.bookingStatus,
      conversionStatus: dto.conversionStatus,
      salesOrderId: dto.salesOrderId,
      salesOrderNumber: dto.salesOrderNumber,
      salesInvoiceId: dto.salesInvoiceId,
      canPayBalance,
      preorder: dto,
    };
  }

  /**
   * 11. POST /api/v1/preorders/:id/balance-checkout
   * Creates an idempotent server-generated payable quote & checkout order payload for the
   * current authoritative remaining balance (Sections 6 & 9).
   */
  async function createPreorderBalanceCheckout(params: {
    preorderId: string;
    requesterUid: string;
    customerDisplayName?: string;
    customerEmail?: string;
    customerMobile?: string;
    deliveryAddress?: unknown;
    shippingAddress?: unknown;
    idempotencyKey?: string;
  }) {
    const { preorderId, requesterUid } = params;
    if (!isValidId(preorderId)) {
      throw new PreorderDomainError('VALIDATION_ERROR', 'Invalid preorder ID.', 400);
    }

    const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);
    return adminDb.runTransaction(async (tx: any) => {
      const snap = await tx.get(preorderRef);
      if (!snap.exists) {
        throw new PreorderDomainError('NOT_FOUND', 'Pre-order booking not found.', 404);
      }

      const data = snap.data() || {};
      if (data.userId !== requesterUid && data.customerId !== requesterUid) {
        throw new PreorderDomainError(
          'FORBIDDEN',
          'You do not have permission to initiate balance payment for this pre-order.',
          403
        );
      }

      const dto = toBookingDto(data);
      if (dto.bookingStatus === 'cancelled') {
        throw new PreorderDomainError(
          'CONFLICT',
          'Cancelled pre-order booking cannot accept a remaining balance payment.',
          409
        );
      }
      if (
        dto.conversionStatus === 'converted' ||
        dto.salesOrderId ||
        dto.paymentStatus === 'paid' ||
        dto.remainingBalance <= 0
      ) {
        throw new PreorderDomainError(
          'CONFLICT',
          'This pre-order booking is already fully paid and has no remaining balance.',
          409
        );
      }

      const nowIso = getNow().toISOString();
      const rawAddressInput = params.deliveryAddress ?? params.shippingAddress;
      const addrNorm =
        rawAddressInput !== undefined
          ? normalizeDeliveryAddress(rawAddressInput)
          : normalizeDeliveryAddress(data.deliveryAddress ?? data.shippingAddress ?? data);

      let activeRecord = data;
      if (rawAddressInput !== undefined && addrNorm.deliveryAddress) {
        activeRecord = {
          ...data,
          ...addrNorm,
          updatedAt: nowIso,
        };
        tx.set(preorderRef, activeRecord, { merge: true });
      }

      const activeDto = toBookingDto(activeRecord);
      const authoritativeBalance = roundMoney(
        Math.max(0, activeDto.totalProductValue - activeDto.totalVerifiedPaid)
      );
      if (authoritativeBalance <= 0) {
        throw new PreorderDomainError(
          'CONFLICT',
          'No remaining balance is due for this pre-order booking.',
          409
        );
      }

      const cleanIdem = String(params.idempotencyKey || '')
        .replace(/[^A-Za-z0-9_-]/g, '')
        .slice(0, 32);
      const checkoutId = cleanIdem
        ? `BAL-${activeDto.preorderId}-${cleanIdem}`
        : `BAL-${activeDto.preorderId}-${getNow().getTime()}`;

      const orderData = {
        id: checkoutId,
        customerId: requesterUid,
        customerName:
          params.customerDisplayName ||
          activeDto.deliveryAddressName ||
          activeDto.customerDisplayName ||
          'LeafyEarth Customer',
        customerEmail: params.customerEmail || activeDto.deliveryAddressEmail || '',
        customerMobile: params.customerMobile || activeDto.deliveryAddressMobile || '',
        shippingAddress: activeDto.shippingAddress || activeDto.deliveryAddress,
        deliveryAddress: activeDto.deliveryAddress,
        deliveryFee: 0,
        discount: 0,
        regularInvoiceGrandTotal: 0,
        totalPreorderBookingAdvance: authoritativeBalance,
        customerGrandTotalPayable: authoritativeBalance,
        totalValue: authoritativeBalance,
        paymentMethod: 'Razorpay',
        paymentStatus: 'Pending',
        orderStatus: 'Pending',
        deliveryStatus: 'Pending',
        products: [
          {
            id: activeDto.productId,
            productId: activeDto.productId,
            productName: activeDto.productNameSnapshot,
            imageUrl: activeDto.imageUrlSnapshot,
            quantity: activeDto.quantity,
            price: authoritativeBalance,
            unitPrice: activeDto.onlinePriceSnapshot,
            packingSize: activeDto.packingSizeSnapshot,
            gstPercentage: activeDto.gstPercentageSnapshot,
            isPreorder: true,
            isPreorderBalancePayment: true,
            preorderId: activeDto.preorderId,
            bookingReference: activeDto.preorderId,
            onlinePriceSnapshot: activeDto.onlinePriceSnapshot,
            totalProductValue: activeDto.totalProductValue,
            paymentType: 'balance',
            paymentTypeLabel: 'Remaining Balance Payment',
            bookingAdvance: authoritativeBalance,
            remainingBalance: 0,
            giftWrap: activeDto.giftWrap,
            specialSuggestion: activeDto.specialSuggestion,
            expectedDeliveryDate: activeDto.expectedDeliveryDate,
            preferredCourierAgent: activeDto.preferredCourierAgent,
            deliveryAddress: activeDto.deliveryAddress,
          },
        ],
      };

      return {
        checkoutId,
        preorderId: activeDto.preorderId,
        payableAmount: authoritativeBalance,
        totalProductValue: activeDto.totalProductValue,
        initialBookingAdvance: activeDto.initialBookingAdvance,
        totalVerifiedPaid: activeDto.totalVerifiedPaid,
        remainingBalance: authoritativeBalance,
        currency: activeDto.currency,
        orderData,
        preorder: activeDto,
      };
    });
  }

  /**
   * 12. POST /api/v1/admin/preorders/:id/reconcile
   * Protected admin/internal reconciliation endpoint to retry or repair conversion of an
   * already verified fully-paid pre-order without charging the customer again (Sections 9 & 10).
   */
  async function reconcilePreorderConversion(params: {
    preorderId: string;
    adminUid: string;
    note?: string;
  }) {
    const result = await convertFullyPaidPreorderToSalesOrder({
      preorderId: params.preorderId,
      actorId: params.adminUid,
      actorRole: 'admin',
      note: params.note || 'Admin reconciliation triggered',
    });

    if (!result.converted) {
      throw new PreorderDomainError(
        'CONFLICT',
        result.reason || 'Pre-order booking is not eligible for sales order conversion.',
        409
      );
    }

    return {
      converted: result.converted,
      idempotentReplay: result.idempotentReplay,
      preorder: result.booking,
      salesOrderId: result.salesOrderId,
      salesOrderNumber: result.salesOrderNumber,
      salesOrder: result.salesOrder,
    };
  }

  return {
    listEligibleProducts,
    listCourierAgents,
    createPreorder,
    updatePreorderDetails,
    convertFullyPaidPreorderToSalesOrder,
    confirmPreorderPaymentsForCheckout,
    failPreorderPaymentsForCheckout,
    getPreorderById,
    getPreorderBalanceQuote,
    createPreorderBalanceCheckout,
    reconcilePreorderConversion,
    listMyPreorders,
    cancelPreorder,
    adminUpdateStatus,
    toBookingDto,
  };
}
