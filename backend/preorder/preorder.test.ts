import test from 'node:test';
import assert from 'node:assert/strict';
import { PreorderDomainError } from './preorderTypes';
import {
  isProductPreorderEligible,
  toEligibleProductDto,
  validateFutureDeliveryDate,
  validateAndComputeAdvance,
  validatePreferredCourierAgent,
  normalizePaymentType,
  normalizeGiftWrap,
  calculateCheckoutFinancials,
  createPreorderService,
} from './preorderService';

test('Strict preorderactive boolean evaluation rejects non-boolean values', () => {
  assert.equal(isProductPreorderEligible({ preorderactive: true }), true);
  assert.equal(isProductPreorderEligible({ preorderactive: false }), false);
  assert.equal(isProductPreorderEligible({ preorderactive: 'true' }), false);
  assert.equal(isProductPreorderEligible({ preorderactive: 1 }), false);
  assert.equal(isProductPreorderEligible({ preorderactive: null }), false);
  assert.equal(isProductPreorderEligible({}), false);
  assert.equal(isProductPreorderEligible(null), false);
});

test('toEligibleProductDto maps eligible product snapshot correctly', () => {
  const eligible = toEligibleProductDto('prod-2', {
    name: 'Fresh Saffron Batch',
    onlinePrice: 899,
    offerPrice: 799,
    shopPrice: 999,
    preorderactive: true,
    packingSize: '10g',
  });
  assert.equal(eligible.id, 'prod-2');
  assert.equal(eligible.preorderactive, true);
  assert.equal(eligible.onlinePrice, 899);
  assert.equal(eligible.offerPrice, 799);
  assert.equal(eligible.effectivePrice, 799);
});

test('Booking Advance validation: Full Amount sets advance = 100% and remainingBalance = 0', () => {
  const calc = validateAndComputeAdvance({
    onlinePriceSnapshot: 500,
    quantity: 2,
    paymentType: 'full',
  });
  assert.equal(calc.totalProductValue, 1000);
  assert.equal(calc.bookingAdvance, 1000);
  assert.equal(calc.remainingBalance, 0);
  assert.equal(calc.minBookingAdvance, 100);
});

test('Booking Advance validation: Partial Payment boundary tests (10% min, 100% max)', () => {
  // Exact 10% minimum boundary -> valid
  const minBoundary = validateAndComputeAdvance({
    onlinePriceSnapshot: 500,
    quantity: 2,
    paymentType: 'partial',
    rawBookingAdvance: 100,
  });
  assert.equal(minBoundary.totalProductValue, 1000);
  assert.equal(minBoundary.bookingAdvance, 100);
  assert.equal(minBoundary.remainingBalance, 900);

  // Exact 100% maximum boundary -> valid
  const maxBoundary = validateAndComputeAdvance({
    onlinePriceSnapshot: 500,
    quantity: 2,
    paymentType: 'partial',
    rawBookingAdvance: 1000,
  });
  assert.equal(maxBoundary.bookingAdvance, 1000);
  assert.equal(maxBoundary.remainingBalance, 0);

  // Below 10% -> rejected
  assert.throws(
    () =>
      validateAndComputeAdvance({
        onlinePriceSnapshot: 500,
        quantity: 2,
        paymentType: 'partial',
        rawBookingAdvance: 99.99,
      }),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );

  // Above 100% -> rejected
  assert.throws(
    () =>
      validateAndComputeAdvance({
        onlinePriceSnapshot: 500,
        quantity: 2,
        paymentType: 'partial',
        rawBookingAdvance: 1000.01,
      }),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );

  // Zero, negative, or NaN -> rejected
  for (const invalidVal of [0, -50, Number.NaN, 'abc']) {
    assert.throws(
      () =>
        validateAndComputeAdvance({
          onlinePriceSnapshot: 500,
          quantity: 1,
          paymentType: 'partial',
          rawBookingAdvance: invalidVal,
        }),
      (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
    );
  }
});

test('Expected Date of Delivery validation rejects past and today dates, accepts future dates', () => {
  const now = new Date('2026-11-10T10:00:00+05:30');
  assert.throws(
    () => validateFutureDeliveryDate('2026-11-09', now),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );
  assert.throws(
    () => validateFutureDeliveryDate('2026-11-10', now),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );
  assert.equal(validateFutureDeliveryDate('2026-11-11', now), '2026-11-11');
});

test('Courier agent, payment type, and gift wrap validation', () => {
  assert.equal(normalizePaymentType('Full Amount').paymentType, 'full');
  assert.equal(normalizePaymentType('Partial Payment').paymentType, 'partial');
  assert.throws(
    () => normalizePaymentType('invalid_type'),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );

  assert.equal(normalizeGiftWrap(true), true);
  assert.equal(normalizeGiftWrap('Yes'), true);
  assert.equal(normalizeGiftWrap(false), false);
  assert.equal(normalizeGiftWrap('No'), false);

  assert.equal(validatePreferredCourierAgent('Amazon Shipping'), 'Amazon Shipping');
  assert.equal(validatePreferredCourierAgent('Delhivery'), 'Delhivery');
  assert.equal(validatePreferredCourierAgent('India Post'), 'India Post');
  assert.equal(validatePreferredCourierAgent('DTDC'), 'DTDC');
  assert.throws(
    () => validatePreferredCourierAgent('BlueDart'),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );
  assert.throws(
    () => validatePreferredCourierAgent(''),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'VALIDATION_ERROR'
  );
});

test('Checkout financial calculations: Mixed cart vs Pre-order-only cart', () => {
  // Mixed cart: Regular sales subtotal = 1000, GST = 152.54, delivery = 50, discount = 0, Pre-order advance = 300
  const mixed = calculateCheckoutFinancials({
    regularItems: [{ price: 500, quantity: 2, gstPercentage: 18 }],
    preorderItems: [{ bookingAdvance: 300, totalProductValue: 1000, remainingBalance: 700 }],
    deliveryFee: 50,
    discount: 0,
  });
  assert.equal(mixed.regularSalesSubtotal, 1000);
  assert.equal(mixed.regularSalesGst, 152.54);
  assert.equal(mixed.regularInvoiceGrandTotal, 1050);
  assert.equal(mixed.totalPreorderBookingAdvance, 300);
  assert.equal(mixed.customerGrandTotalPayable, 1350);

  // Pre-order-only cart: Regular invoice grand total = 0, GST = 0, Customer payable = Pre-order advance
  const preorderOnly = calculateCheckoutFinancials({
    regularItems: [],
    preorderItems: [
      { bookingAdvance: 250, totalProductValue: 500, remainingBalance: 250 },
      { bookingAdvance: 450, totalProductValue: 450, remainingBalance: 0 },
    ],
    deliveryFee: 50, // ignored when no regular items
    discount: 0,
  });
  assert.equal(preorderOnly.regularSalesSubtotal, 0);
  assert.equal(preorderOnly.regularSalesGst, 0);
  assert.equal(preorderOnly.regularInvoiceGrandTotal, 0);
  assert.equal(preorderOnly.totalPreorderBookingAdvance, 700);
  assert.equal(preorderOnly.customerGrandTotalPayable, 700);
});

test('Payment verification confirms preorders (paid vs partially_paid), writes payment_allocations, and never touches sales_orders', async () => {
  const store: Record<string, Record<string, any>> = {
    preorders: {
      'PO-FULL-1': {
        preorderId: 'PO-FULL-1',
        userId: 'user-1',
        productId: 'prod-1',
        productNameSnapshot: 'Almond Oil',
        onlinePriceSnapshot: 500,
        quantity: 1,
        totalProductValue: 500,
        bookingAdvance: 500,
        remainingBalance: 0,
        paymentType: 'full',
        bookingStatus: 'pending_payment',
        paymentStatus: 'unpaid',
      },
      'PO-PARTIAL-1': {
        preorderId: 'PO-PARTIAL-1',
        userId: 'user-1',
        productId: 'prod-2',
        productNameSnapshot: 'Saffron',
        onlinePriceSnapshot: 1000,
        quantity: 1,
        totalProductValue: 1000,
        bookingAdvance: 200,
        remainingBalance: 800,
        paymentType: 'partial',
        bookingStatus: 'pending_payment',
        paymentStatus: 'unpaid',
      },
    },
    payment_allocations: {},
    preorder_events: {},
    sales_orders: {},
  };

  const mockDb: any = {
    collection: (colName: string) => ({
      doc: (docId: string) => ({
        _col: colName,
        _id: docId,
      }),
    }),
    runTransaction: async (fn: (tx: any) => Promise<any>) => {
      const tx = {
        get: async (ref: { _col: string; _id: string }) => {
          const docData = store[ref._col]?.[ref._id];
          return {
            exists: Boolean(docData),
            data: () => docData,
          };
        },
        set: (ref: { _col: string; _id: string }, data: any, opts?: { merge?: boolean }) => {
          store[ref._col] = store[ref._col] || {};
          store[ref._col][ref._id] = opts?.merge
            ? { ...(store[ref._col][ref._id] || {}), ...data }
            : data;
        },
      };
      return fn(tx);
    },
  };

  const service = createPreorderService({ adminDb: mockDb });
  const result = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: 'ORD-TEST-100',
    paymentReference: 'pay_test_999',
    userId: 'user-1',
    preorderIds: ['PO-FULL-1', 'PO-PARTIAL-1'],
    regularSalesOrderId: 'ORD-TEST-100',
    regularSalesAmount: 400,
    invoiceId: 'INV-ORD-TEST-100',
  });

  assert.equal(result.allocation.regularSalesAmount, 400);
  assert.equal(result.allocation.totalPreorderAdvance, 700);
  assert.equal(result.allocation.customerGrandTotalPayable, 1100);

  // Full payment booking marked confirmed + paid
  assert.equal(store.preorders['PO-FULL-1'].bookingStatus, 'confirmed');
  assert.equal(store.preorders['PO-FULL-1'].paymentStatus, 'paid');

  // Partial payment booking marked confirmed + partially_paid
  assert.equal(store.preorders['PO-PARTIAL-1'].bookingStatus, 'confirmed');
  assert.equal(store.preorders['PO-PARTIAL-1'].paymentStatus, 'partially_paid');

  // Payment allocation saved, sales_orders untouched by preorder service
  assert.ok(store.payment_allocations['ORD-TEST-100']);
  assert.equal(Object.keys(store.sales_orders).length, 0);

  // Idempotent replay does not double-count
  const replay = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: 'ORD-TEST-100',
    paymentReference: 'pay_test_999',
    userId: 'user-1',
    preorderIds: ['PO-FULL-1', 'PO-PARTIAL-1'],
    regularSalesOrderId: 'ORD-TEST-100',
    regularSalesAmount: 400,
    invoiceId: 'INV-ORD-TEST-100',
  });
  assert.equal(replay.idempotentReplay, true);

  // Remaining balance payment settles partially_paid booking to paid with 0 remainingBalance
  const balanceResult = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: 'BAL-PO-PARTIAL-1-200',
    paymentReference: 'pay_balance_888',
    userId: 'user-1',
    preorderIds: ['PO-PARTIAL-1'],
    regularSalesOrderId: null,
    regularSalesAmount: 0,
    preorderItemOverrides: [
      {
        preorderId: 'PO-PARTIAL-1',
        bookingAdvance: 800,
        isBalancePayment: true,
      },
    ],
  });
  assert.equal(balanceResult.allocation.totalPreorderAdvance, 800);
  assert.equal(balanceResult.allocation.customerGrandTotalPayable, 800);
  assert.equal(store.preorders['PO-PARTIAL-1'].paymentStatus, 'paid');
  assert.equal(store.preorders['PO-PARTIAL-1'].bookingAdvance, 1000);
  assert.equal(store.preorders['PO-PARTIAL-1'].remainingBalance, 0);

  // Updating pre-order item via updatePreorderDetails stores deliveryAddress in preorders table
  const updatedDto = await service.updatePreorderDetails({
    preorderId: 'PO-FULL-1',
    requesterUid: 'user-1',
    deliveryAddress: {
      id: 'addr-1',
      name: 'Jojo',
      mobileNumber: '9876543210',
      addressLine: 'Kallettumkara',
      city: 'Thrissur',
      district: 'Thrissur',
      state: 'Kerala',
      pincode: '680683',
    },
    preferredCourierAgent: 'Amazon Shipping',
  });
  assert.equal(updatedDto.preferredCourierAgent, 'Amazon Shipping');
  assert.equal(updatedDto.deliveryPincode, '680683');
  assert.equal(updatedDto.deliveryState, 'Kerala');
  assert.equal(store.preorders['PO-FULL-1'].deliveryAddressLine, 'Kallettumkara');
  assert.equal(store.preorders['PO-FULL-1'].deliveryPincode, '680683');

  // Failed or cancelled payment NEVER writes to preorders or preorder_idempotency, and updates preorder_events
  const preordersCountBeforeFail = Object.keys(store.preorders).length;
  store.preorder_idempotency = store.preorder_idempotency || {};
  const idemCountBeforeFail = Object.keys(store.preorder_idempotency).length;

  const failRes = await service.failPreorderPaymentsForCheckout({
    checkoutReference: 'ORD-FAIL-1',
    paymentReference: 'pay_fail_1',
    userId: 'user-1',
    preorderIds: ['PO-UNPAID-1'],
    preorderItems: [
      {
        preorderId: 'PO-UNPAID-1',
        productId: 'prod-1',
        productName: 'Almond Oil',
        quantity: 2,
        paymentType: 'partial',
        bookingAdvance: 200,
        remainingBalance: 800,
        totalProductValue: 1000,
        expectedDeliveryDate: '2026-12-01',
        preferredCourierAgent: 'DTDC',
      },
    ],
    outcome: 'failed',
    reason: 'Signature mismatch',
  });
  assert.equal(Object.keys(store.preorders).length, preordersCountBeforeFail);
  assert.equal(store.preorders['PO-UNPAID-1'], undefined);
  assert.equal(Object.keys(store.preorder_idempotency).length, idemCountBeforeFail);
  assert.equal(failRes.events.length, 1);
  assert.equal(failRes.events[0].eventType, 'preorder.payment_failed');
  assert.equal(failRes.events[0].paymentStatus, 'failed');
  assert.equal(failRes.events[0].reason, 'Signature mismatch');
  assert.ok(store.preorder_events['poe_ORD-FAIL-1_PO-UNPAID-1']);
});

test('Pre-payment createPreorder does NOT add records to preorders, preorder_idempotency, or preorder_events; records are created ONLY after successful payment', async () => {
  const store: Record<string, Record<string, any>> = {
    products: {
      'prod-plum-1': {
        id: 'prod-plum-1',
        name: 'Plum Cake - Rum Soaked',
        sku: 'PLUM-900',
        packingSize: '900 gm',
        onlinePrice: 1699,
        offerPrice: 1699,
        mrp: 1799,
        gstPercentage: 12,
        preorderactive: true,
      },
    },
    preorders: {},
    preorder_idempotency: {},
    preorder_events: {},
    payment_allocations: {},
    sales_orders: {},
  };

  const mockDb: any = {
    collection: (colName: string) => ({
      doc: (docId: string) => ({
        _col: colName,
        _id: docId,
      }),
    }),
    runTransaction: async (fn: (tx: any) => Promise<any>) => {
      const tx = {
        get: async (ref: { _col: string; _id: string }) => {
          const docData = store[ref._col]?.[ref._id];
          return {
            exists: Boolean(docData),
            data: () => docData,
          };
        },
        set: (ref: { _col: string; _id: string }, data: any, opts?: { merge?: boolean }) => {
          store[ref._col] = store[ref._col] || {};
          store[ref._col][ref._id] = opts?.merge
            ? { ...(store[ref._col][ref._id] || {}), ...data }
            : data;
        },
      };
      return fn(tx);
    },
  };

  const now = new Date('2026-11-11T10:00:00+05:30');
  const service = createPreorderService({ adminDb: mockDb, now: () => now });

  // 1. Pre-Order Booking clicked on Product Details -> validates & returns DTO, but writes NOTHING to DB tables
  const created = await service.createPreorder({
    userId: 'user-99',
    customerId: 'user-99',
    customerDisplayName: 'Jojo',
    productId: 'prod-plum-1',
    quantity: 1,
    paymentType: 'partial',
    bookingAdvance: 200,
    giftWrap: false,
    specialSuggestion: 'Pack carefully',
    expectedDeliveryDate: '2026-11-20',
    preferredCourierAgent: 'India Post',
    idempotencyKey: 'idem_user99_plum1',
  });

  assert.ok(created.booking.preorderId.startsWith('po_'));
  assert.equal(created.booking.bookingAdvance, 200);
  assert.equal(created.booking.remainingBalance, 1499);
  assert.equal(Object.keys(store.preorders).length, 0);
  assert.equal(Object.keys(store.preorder_idempotency).length, 0);
  assert.equal(Object.keys(store.preorder_events).length, 0);

  // 2. If payment generation or checkout is cancelled -> updates ONLY preorder_events, NOT preorders or preorder_idempotency
  await service.failPreorderPaymentsForCheckout({
    checkoutReference: 'TXN-CANCEL-101',
    userId: 'user-99',
    preorderIds: [created.booking.preorderId],
    preorderItems: [
      {
        preorderId: created.booking.preorderId,
        productId: 'prod-plum-1',
        productName: 'Plum Cake - Rum Soaked',
        quantity: 1,
        paymentType: 'partial',
        bookingAdvance: 200,
        remainingBalance: 1499,
        totalProductValue: 1699,
        expectedDeliveryDate: '2026-11-20',
        preferredCourierAgent: 'India Post',
      },
    ],
    outcome: 'cancelled',
    reason: 'Payment cancelled by customer during checkout.',
  });

  assert.equal(Object.keys(store.preorders).length, 0);
  assert.equal(Object.keys(store.preorder_idempotency).length, 0);
  assert.equal(Object.keys(store.preorder_events).length, 1);
  const cancelEvent = Object.values(store.preorder_events)[0];
  assert.equal(cancelEvent.eventType, 'preorder.payment_cancelled');
  assert.equal(cancelEvent.paymentStatus, 'cancelled');
  assert.equal(cancelEvent.preorderId, created.booking.preorderId);

  // 3. When payment succeeds -> creates records in preorders, preorder_idempotency, and preorder_events
  const confirmed = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: 'TXN-SUCCESS-102',
    paymentReference: 'pay_rzp_live_102',
    userId: 'user-99',
    customerId: 'user-99',
    customerDisplayName: 'Jojo',
    regularSalesOrderId: null,
    regularSalesAmount: 0,
    preorderIds: [created.booking.preorderId],
    deliveryAddress: {
      name: 'Jojo',
      mobileNumber: '9876543210',
      addressLine: 'Kallettumkara',
      city: 'Thrissur',
      district: 'Thrissur',
      state: 'Kerala',
      pincode: '680683',
    },
    preorderItemOverrides: [
      {
        preorderId: created.booking.preorderId,
        productId: 'prod-plum-1',
        productName: 'Plum Cake - Rum Soaked',
        quantity: 1,
        paymentType: 'partial',
        bookingAdvance: 200,
        giftWrap: false,
        specialSuggestion: 'Pack carefully',
        expectedDeliveryDate: '2026-11-20',
        preferredCourierAgent: 'India Post',
        idempotencyKey: 'idem_user99_plum1',
      },
    ],
  });

  assert.equal(confirmed.bookings.length, 1);
  assert.equal(Object.keys(store.preorders).length, 1);
  assert.equal(Object.keys(store.preorder_idempotency).length, 1);
  assert.equal(store.preorders[created.booking.preorderId].bookingStatus, 'confirmed');
  assert.equal(store.preorders[created.booking.preorderId].paymentStatus, 'partially_paid');
  assert.equal(store.preorders[created.booking.preorderId].deliveryPincode, '680683');
  assert.ok(store.preorder_idempotency['user-99__idem_user99_plum1']);
  assert.equal(Object.keys(store.preorder_events).length, 2); // 1 cancelled + 1 confirmed
});
