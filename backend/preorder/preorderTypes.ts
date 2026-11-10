/**
 * LeafyEarth Pre-Order Booking Module — Types, DTOs, Error Codes & Configuration.
 *
 * Supports product-level pre-order bookings with Full Amount or Partial Payment (10%–100%)
 * advance payments integrated with the existing shopping cart, checkout, payment gateway,
 * and invoice infrastructure.
 */

export type PreorderErrorCode =
  | 'PRODUCT_NOT_PREORDERABLE'
  | 'PRODUCT_NOT_FOUND'
  | 'UNAUTHENTICATED'
  | 'FORBIDDEN'
  | 'CONFLICT'
  | 'INVALID_STATUS_TRANSITION'
  | 'CANCELLATION_NOT_ALLOWED'
  | 'VALIDATION_ERROR'
  | 'NOT_FOUND'
  | 'RATE_LIMITED'
  | 'INTERNAL_ERROR';

export class PreorderDomainError extends Error {
  public readonly code: PreorderErrorCode;
  public readonly httpStatus: number;

  constructor(code: PreorderErrorCode, message: string, httpStatus = 400) {
    super(message);
    this.name = 'PreorderDomainError';
    this.code = code;
    this.httpStatus = httpStatus;
  }
}

export type PreorderBookingStatus =
  | 'pending_payment'
  | 'confirmed'
  | 'processing'
  | 'ready_for_dispatch'
  | 'dispatched'
  | 'delivered'
  | 'cancelled';

/** Alias kept for route/service status transition helpers */
export type PreorderStatus = PreorderBookingStatus;

export type PreorderPaymentStatus =
  | 'unpaid'
  | 'pending'
  | 'partially_paid'
  | 'paid'
  | 'failed'
  | 'refunded';

export type PreorderPaymentType = 'full' | 'partial';

export type PreorderPaymentTypeLabel = 'Full Amount' | 'Partial Payment';

export interface PreorderConfig {
  timezone: string;
  timezoneOffsetMinutes: number; // +330 for Asia/Kolkata (IST)
  minQuantity: number;
  maxQuantity: number;
  minAdvanceRatio: number; // 0.10 (10%)
  maxAdvanceRatio: number; // 1.00 (100%)
  maxSpecialSuggestionLength: number;
  currency: string;
  defaultCourierAgents: string[];
}

const envInt = (key: string, fallback: number): number => {
  const raw = process.env[key];
  if (!raw) return fallback;
  const parsed = parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

export const DEFAULT_COURIER_AGENTS: string[] = [
  'India Post',
  'DTDC',
  'BlueDart',
  'Delhivery',
  'Professional Couriers',
  'ST Courier',
  'Trackon',
  'Ekart',
  'XpressBees',
  'Standard Courier',
];

export const DEFAULT_PREORDER_CONFIG: PreorderConfig = {
  timezone: process.env.PREORDER_TIMEZONE || 'Asia/Kolkata',
  timezoneOffsetMinutes: 330,
  minQuantity: 1,
  maxQuantity: envInt('PREORDER_MAX_QUANTITY', 20),
  minAdvanceRatio: 0.1,
  maxAdvanceRatio: 1.0,
  maxSpecialSuggestionLength: 500,
  currency: 'INR',
  defaultCourierAgents: DEFAULT_COURIER_AGENTS,
};

export const ALLOWED_STATUS_TRANSITIONS: Record<PreorderBookingStatus, PreorderBookingStatus[]> = {
  pending_payment: ['confirmed', 'cancelled'],
  confirmed: ['processing', 'cancelled'],
  processing: ['ready_for_dispatch', 'cancelled'],
  ready_for_dispatch: ['dispatched'],
  dispatched: ['delivered'],
  delivered: [],
  cancelled: [],
};

export interface PreorderBookingDto {
  preorderId: string;
  userId: string;
  customerId: string;
  customerDisplayName: string;
  productId: string;
  productNameSnapshot: string;
  skuSnapshot: string;
  packingSizeSnapshot: string;
  imageUrlSnapshot: string | null;
  quantity: number;
  onlinePriceSnapshot: number;
  mrpSnapshot: number;
  gstPercentageSnapshot: number;
  totalProductValue: number;
  paymentType: PreorderPaymentType;
  paymentTypeLabel: PreorderPaymentTypeLabel;
  bookingAdvance: number;
  remainingBalance: number;
  giftWrap: boolean;
  specialSuggestion: string;
  expectedDeliveryDate: string; // YYYY-MM-DD (future date)
  preferredCourierAgent: string;
  currency: string;
  bookingStatus: PreorderBookingStatus;
  /** Alias for bookingStatus for UI convenience */
  status: PreorderBookingStatus;
  paymentStatus: PreorderPaymentStatus;
  paymentReference: string | null;
  checkoutReference: string | null;
  invoiceId: string | null;
  idempotencyKey: string;
  createdAt: string;
  updatedAt: string;
  canCancel: boolean;
}

export interface PreorderPaymentAllocationItemDto {
  preorderId: string;
  productId: string;
  productName: string;
  quantity: number;
  onlinePriceSnapshot: number;
  totalProductValue: number;
  paymentType: PreorderPaymentType;
  paymentTypeLabel: PreorderPaymentTypeLabel;
  bookingAdvance: number;
  remainingBalance: number;
  giftWrap: boolean;
  specialSuggestion: string;
  expectedDeliveryDate: string;
  preferredCourierAgent: string;
}

export interface PaymentAllocationDto {
  checkoutReference: string;
  paymentReference: string | null;
  userId: string;
  regularSalesOrderId: string | null;
  regularSalesAmount: number;
  totalPreorderAdvance: number;
  customerGrandTotalPayable: number;
  paymentStatus: PreorderPaymentStatus;
  preorderIds: string[];
  allocations: PreorderPaymentAllocationItemDto[];
  createdAt: string;
  updatedAt: string;
}
