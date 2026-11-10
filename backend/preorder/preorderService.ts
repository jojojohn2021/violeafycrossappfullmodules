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
  PreorderDomainError,
  type PreorderPaymentAllocationItemDto,
  type PreorderPaymentStatus,
  type PreorderPaymentType,
  type PreorderPaymentTypeLabel,
} from './preorderTypes';

export const COLLECTIONS = {
  PRODUCTS: 'products',
  PREORDERS: 'preorders',
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

/** Validates Preferred Courier Agent string. */
export function validatePreferredCourierAgent(raw: unknown): string {
  const sanitized = sanitizeNotes(raw, 100);
  if (!sanitized) {
    throw new PreorderDomainError('VALIDATION_ERROR', 'Preferred Courier Agent is required.', 400);
  }
  return sanitized;
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
}): { allowed: boolean; reason?: string } {
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
    const remainingBalance = roundMoney(
      Number(data.remainingBalance ?? Math.max(0, totalProductValue - bookingAdvance))
    );

    const cancelCheck = canCustomerCancelBooking({ bookingStatus: rawBookingStatus });

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
      remainingBalance,
      giftWrap: Boolean(data.giftWrap),
      specialSuggestion: String(data.specialSuggestion ?? data.notes ?? ''),
      expectedDeliveryDate: String(data.expectedDeliveryDate || ''),
      preferredCourierAgent: String(data.preferredCourierAgent || 'Standard Courier'),
      currency: String(data.currency || config.currency),
      bookingStatus: rawBookingStatus,
      status: rawBookingStatus,
      paymentStatus: rawPaymentStatus,
      paymentReference: data.paymentReference ? String(data.paymentReference) : null,
      checkoutReference: data.checkoutReference ? String(data.checkoutReference) : null,
      invoiceId: data.invoiceId ? String(data.invoiceId) : null,
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
   * Returns preferred courier agent options from `courier_agencies` merged with defaults.
   */
  async function listCourierAgents(): Promise<{ courierAgents: string[] }> {
    const set = new Set<string>();
    try {
      const snap = await adminDb.collection(COLLECTIONS.COURIER_AGENCIES).get();
      for (const doc of snap.docs || []) {
        const data = doc.data() || {};
        const name = String(data.agencyName || data.name || '').trim();
        if (name && data.isActive !== false) {
          set.add(name);
        }
      }
    } catch (_) {
      // Fallback to default courier list if collection doesn't exist
    }
    for (const c of config.defaultCourierAgents) {
      set.add(c);
    }
    return { courierAgents: Array.from(set) };
  }

  /**
   * 3. POST /api/v1/preorders
   * Validates product eligibility (`preorderactive === true`), quantity, Full Amount vs Partial Payment
   * (10%–100% of Online Price * quantity), Gift Wrap, Special Suggestion, future Expected Date of Delivery,
   * and Preferred Courier Agent inside a Firestore transaction.
   *
   * Creates a pre-order booking record in `preorders/{preorderId}` with:
   *   - `bookingStatus: 'pending_payment'`
   *   - `paymentStatus: 'unpaid'`
   * Does NOT mark the booking as paid and NEVER writes to `sales_orders`.
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
    idempotencyKey: string;
  }): Promise<{ booking: PreorderBookingDto; idempotentReplay: boolean }> {
    const { userId, productId } = params;
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
    const preferredCourierAgent = validatePreferredCourierAgent(params.preferredCourierAgent);

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
          return {
            booking: toBookingDto(existingSnap.data() || {}),
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
      const preorderId = `po_${crypto.randomBytes(12).toString('hex')}`;
      const preorderRef = adminDb.collection(COLLECTIONS.PREORDERS).doc(preorderId);
      const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
      const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);

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
        occurredAt: nowIso,
      });

      return {
        booking: toBookingDto(bookingRecord),
        idempotentReplay: false,
      };
    });
  }

  /**
   * 4. Confirm Pre-Order Payments on Verified Checkout Payment (Section 8.3 & Section 12).
   * - Idempotent: repeated calls with the same `checkoutReference` return existing allocation without double-counting.
   * - Updates each `preorders/{preorderId}`:
   *     - `bookingStatus = 'confirmed'`
   *     - `paymentStatus = 'paid'` (if `paymentType === 'full'` or `remainingBalance === 0`)
   *     - `paymentStatus = 'partially_paid'` (if `paymentType === 'partial'` and `remainingBalance > 0`)
   *     - `paymentReference`, `checkoutReference`, `invoiceId`
   * - Writes `payment_allocations/{checkoutReference}`
   * - NEVER inserts or modifies `sales_orders`.
   */
  async function confirmPreorderPaymentsForCheckout(params: {
    checkoutReference: string;
    paymentReference: string;
    userId: string;
    regularSalesOrderId?: string | null;
    regularSalesAmount: number;
    preorderIds: string[];
    preorderItemOverrides?: Array<{
      preorderId?: string;
      quantity?: number;
      bookingAdvance?: number;
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

    return adminDb.runTransaction(async (tx: any) => {
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

      const nowIso = getNow().toISOString();
      const allocations: PreorderPaymentAllocationItemDto[] = [];
      const updatedBookings: PreorderBookingDto[] = [];
      let totalPreorderAdvance = 0;

      for (let i = 0; i < uniquePreorderIds.length; i++) {
        const snap = preorderSnaps[i];
        const preorderId = uniquePreorderIds[i];
        if (!snap.exists) {
          throw new PreorderDomainError(
            'NOT_FOUND',
            `Pre-order booking '${preorderId}' not found.`,
            404
          );
        }
        const data = snap.data() || {};
        const baseDto = toBookingDto(data);
        const override = (params.preorderItemOverrides || []).find(
          (o) => String(o.preorderId || '') === preorderId
        );
        const finalQty =
          override?.quantity && Number.isInteger(Number(override.quantity)) && Number(override.quantity) >= 1
            ? Number(override.quantity)
            : baseDto.quantity;
        const advanceCalc = validateAndComputeAdvance({
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

        const nextPaymentStatus: PreorderPaymentStatus =
          baseDto.paymentType === 'full' || advanceCalc.remainingBalance <= 0
            ? 'paid'
            : 'partially_paid';

        const updatedRecord = {
          ...data,
          quantity: finalQty,
          totalProductValue: advanceCalc.totalProductValue,
          bookingAdvance: advanceCalc.bookingAdvance,
          remainingBalance: advanceCalc.remainingBalance,
          bookingStatus: 'confirmed' as PreorderBookingStatus,
          status: 'confirmed' as PreorderBookingStatus,
          paymentStatus: nextPaymentStatus,
          paymentReference,
          checkoutReference,
          invoiceId: params.invoiceId || data.invoiceId || checkoutReference,
          updatedAt: nowIso,
        };
        const dto = toBookingDto(updatedRecord);

        tx.set(preorderRefs[i], updatedRecord, { merge: true });

        const eventId = `poe_${crypto.randomBytes(12).toString('hex')}`;
        const eventRef = adminDb.collection(COLLECTIONS.EVENTS).doc(eventId);
        tx.set(eventRef, {
          eventId,
          preorderId,
          actorId: userId || dto.userId,
          actorRole: 'system',
          eventType: 'preorder.payment_confirmed',
          oldStatus: dto.bookingStatus,
          newStatus: 'confirmed',
          paymentStatus: nextPaymentStatus,
          paymentReference,
          checkoutReference,
          bookingAdvance: dto.bookingAdvance,
          remainingBalance: dto.remainingBalance,
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
  }

  /**
   * 5. Record Failed / Cancelled Checkout Payment (Section 12).
   * Ensures failed or cancelled payments NEVER mark pre-order bookings as confirmed or paid.
   */
  async function failPreorderPaymentsForCheckout(params: {
    checkoutReference: string;
    paymentReference?: string | null;
    userId: string;
    regularSalesAmount?: number;
    preorderIds: string[];
    reason?: string;
  }): Promise<{ bookings: PreorderBookingDto[] }> {
    const checkoutReference = String(params.checkoutReference || '').trim();
    const uniquePreorderIds = Array.from(
      new Set((params.preorderIds || []).map((id) => String(id || '').trim()).filter(Boolean))
    );
    if (!checkoutReference || uniquePreorderIds.length === 0) {
      return { bookings: [] };
    }

    const allocRef = adminDb.collection(COLLECTIONS.PAYMENT_ALLOCATIONS).doc(checkoutReference);

    return adminDb.runTransaction(async (tx: any) => {
      const allocSnap = await tx.get(allocRef);
      const preorderRefs = uniquePreorderIds.map((id) =>
        adminDb.collection(COLLECTIONS.PREORDERS).doc(id)
      );
      const preorderSnaps = await Promise.all(preorderRefs.map((ref) => tx.get(ref)));

      // Never downgrade an already confirmed/paid booking
      if (allocSnap.exists && allocSnap.data()?.paymentStatus === 'paid') {
        return {
          bookings: preorderSnaps
            .filter((s) => s.exists)
            .map((s) => toBookingDto(s.data() || {})),
        };
      }

      const nowIso = getNow().toISOString();
      const updatedBookings: PreorderBookingDto[] = [];
      let totalPreorderAdvance = 0;

      for (let i = 0; i < uniquePreorderIds.length; i++) {
        const snap = preorderSnaps[i];
        if (!snap.exists) continue;
        const data = snap.data() || {};
        if (data.paymentStatus === 'paid' || data.paymentStatus === 'partially_paid') {
          updatedBookings.push(toBookingDto(data));
          continue;
        }
        const updatedRecord = {
          ...data,
          bookingStatus: 'pending_payment' as PreorderBookingStatus,
          status: 'pending_payment' as PreorderBookingStatus,
          paymentStatus: 'failed' as PreorderPaymentStatus,
          checkoutReference,
          updatedAt: nowIso,
        };
        tx.set(preorderRefs[i], updatedRecord, { merge: true });
        const dto = toBookingDto(updatedRecord);
        totalPreorderAdvance = roundMoney(totalPreorderAdvance + dto.bookingAdvance);
        updatedBookings.push(dto);
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
          preorderIds: uniquePreorderIds,
          failureReason: sanitizeNotes(params.reason, 300),
          createdAt: allocSnap.exists
            ? String(allocSnap.data()?.createdAt || nowIso)
            : nowIso,
          updatedAt: nowIso,
        },
        { merge: true }
      );

      return { bookings: updatedBookings };
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

  return {
    listEligibleProducts,
    listCourierAgents,
    createPreorder,
    confirmPreorderPaymentsForCheckout,
    failPreorderPaymentsForCheckout,
    getPreorderById,
    listMyPreorders,
    cancelPreorder,
    adminUpdateStatus,
    toBookingDto,
  };
}
