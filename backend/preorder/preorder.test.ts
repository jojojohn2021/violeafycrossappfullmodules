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

test('Payment verification confirms preorders (paid vs partially_paid), converts ONLY fully-paid preorders to sales_orders (deliveryStatus = PRE-ORDER), and converts partially-paid preorders after remaining balance settlement', async () => {
  const store: Record<string, Record<string, any>> = {
    products: {
      'prod-1': { id: 'prod-1', name: 'Almond Oil', stock: 20, unitsSold: 5, revenue: 2500, gstPercentage: 12, hsnCode: '151590' },
      'prod-2': { id: 'prod-2', name: 'Saffron', stock: 15, unitsSold: 2, revenue: 2000, gstPercentage: 5, hsnCode: '091020' },
    },
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
    preorder_idempotency: {},
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

  const service = createPreorderService({
    adminDb: mockDb,
    onSalesOrderCreated: async (so) => ({ invoiceId: `INV-${so.id}` }),
  });
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

  // Flow A: Full payment booking marked confirmed + paid AND converted to sales_orders with deliveryStatus = 'PRE-ORDER'
  assert.equal(store.preorders['PO-FULL-1'].bookingStatus, 'confirmed');
  assert.equal(store.preorders['PO-FULL-1'].paymentStatus, 'paid');
  assert.equal(store.preorders['PO-FULL-1'].conversionStatus, 'converted');
  assert.equal(store.preorders['PO-FULL-1'].salesOrderId, 'SO-PO-PO-FULL-1');
  assert.equal(store.preorders['PO-FULL-1'].salesInvoiceId, 'INV-SO-PO-PO-FULL-1');
  assert.ok(store.sales_orders['SO-PO-PO-FULL-1']);
  assert.equal(store.sales_orders['SO-PO-PO-FULL-1'].deliveryStatus, 'PRE-ORDER');
  assert.equal(store.products['prod-1'].stock, 19);

  // Flow B: Partial payment booking marked confirmed + partially_paid and NEVER creates a sales_orders record
  assert.equal(store.preorders['PO-PARTIAL-1'].bookingStatus, 'confirmed');
  assert.equal(store.preorders['PO-PARTIAL-1'].paymentStatus, 'partially_paid');
  assert.equal(store.preorders['PO-PARTIAL-1'].conversionStatus, 'not_applicable');
  assert.equal(result.bookings[1].salesOrderId, null);
  assert.equal(store.sales_orders['SO-PO-PO-PARTIAL-1'], undefined);
  assert.equal(store.products['prod-2'].stock, 15);

  // Payment allocation saved, only the 1 fully-paid preorder converted
  assert.ok(store.payment_allocations['ORD-TEST-100']);
  assert.equal(Object.keys(store.sales_orders).length, 1);

  // Idempotent replay does not double-count or create duplicate sales orders
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
  assert.equal(Object.keys(store.sales_orders).length, 1);
  assert.equal(store.products['prod-1'].stock, 19);

  // Flow C: Remaining balance payment settles partially_paid booking to paid with 0 remainingBalance and automatically converts to sales_orders
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
  assert.equal(store.preorders['PO-PARTIAL-1'].initialBookingAdvance, 200);
  assert.equal(store.preorders['PO-PARTIAL-1'].totalVerifiedPaid, 1000);
  assert.equal(store.preorders['PO-PARTIAL-1'].bookingAdvance, 1000);
  assert.equal(store.preorders['PO-PARTIAL-1'].remainingBalance, 0);
  assert.equal(store.preorders['PO-PARTIAL-1'].conversionStatus, 'converted');
  assert.equal(store.preorders['PO-PARTIAL-1'].salesOrderId, 'SO-PO-PO-PARTIAL-1');
  assert.equal(store.preorders['PO-PARTIAL-1'].salesInvoiceId, 'INV-SO-PO-PO-PARTIAL-1');
  assert.ok(store.sales_orders['SO-PO-PO-PARTIAL-1']);
  assert.equal(store.sales_orders['SO-PO-PO-PARTIAL-1'].deliveryStatus, 'PRE-ORDER');
  assert.equal(store.products['prod-2'].stock, 14);
  assert.equal(Object.keys(store.sales_orders).length, 2);

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

test('Spec Section 2/4/5/6/8/9/10: ₹1,699.00 Plum Cake Full Booking (Flow A), ₹169.90 Partial Advance (Flow B), ₹1,529.10 Balance Checkout & Settlement (Flow C), and Admin Reconciliation Recovery', async () => {
  const store: Record<string, Record<string, any>> = {
    products: {
      'prod-plum-1699': {
        id: 'prod-plum-1699',
        name: 'Plum Cake - Rum Soaked',
        sku: 'PLUM-900',
        packingSize: '900 gm',
        onlinePrice: 1699,
        offerPrice: 1699,
        mrp: 1799,
        gstPercentage: 12,
        hsnCode: '19059010',
        stock: 50,
        unitsSold: 10,
        revenue: 16990,
        preorderactive: true,
      },
    },
    preorders: {},
    preorder_idempotency: {},
    preorder_events: {},
    payment_allocations: {},
    sales_orders: {},
  };

  let failDownstreamInvoiceOnce = false;
  const createdInvoices: string[] = [];

  const mockDb: any = {
    collection: (colName: string) => ({
      doc: (docId: string) => ({
        _col: colName,
        _id: docId,
        get: async () => {
          const docData = store[colName]?.[docId];
          return {
            exists: Boolean(docData),
            data: () => docData,
          };
        },
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

  const now = new Date('2026-11-12T10:00:00+05:30');
  const service = createPreorderService({
    adminDb: mockDb,
    now: () => now,
    onSalesOrderCreated: async (salesOrder) => {
      if (failDownstreamInvoiceOnce) {
        failDownstreamInvoiceOnce = false;
        throw new Error('Simulated downstream invoice service outage');
      }
      const invId = `INV-${salesOrder.id}`;
      createdInvoices.push(invId);
      return { invoiceId: invId };
    },
  });

  // ---------------------------------------------------------------------------
  // FLOW A: Full payment ₹1,699.00 at initial booking
  // ---------------------------------------------------------------------------
  const fullDraft = await service.createPreorder({
    userId: 'cust-1',
    customerId: 'cust-1',
    customerDisplayName: 'Swapna',
    productId: 'prod-plum-1699',
    quantity: 1,
    paymentType: 'full',
    bookingAdvance: 1699.00,
    giftWrap: false,
    specialSuggestion: '',
    expectedDeliveryDate: '2026-12-09',
    preferredCourierAgent: 'DTDC',
    idempotencyKey: 'idem_flow_a_1699',
  });

  const flowARes = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: 'CHK-FLOW-A-1',
    paymentReference: 'pay_flow_a_1699',
    userId: 'cust-1',
    customerId: 'cust-1',
    customerDisplayName: 'Swapna',
    regularSalesOrderId: null,
    regularSalesAmount: 0,
    preorderIds: [fullDraft.booking.preorderId],
    preorderItemOverrides: [
      {
        preorderId: fullDraft.booking.preorderId,
        productId: 'prod-plum-1699',
        quantity: 1,
        paymentType: 'full',
        bookingAdvance: 1699.00,
        expectedDeliveryDate: '2026-12-09',
        preferredCourierAgent: 'DTDC',
        idempotencyKey: 'idem_flow_a_1699',
      },
    ],
  });

  assert.equal(flowARes.bookings.length, 1);
  assert.equal(flowARes.bookings[0].paymentStatus, 'paid');
  assert.equal(flowARes.bookings[0].totalVerifiedPaid, 1699.00);
  assert.equal(flowARes.bookings[0].remainingBalance, 0);
  assert.equal(flowARes.bookings[0].conversionStatus, 'converted');
  assert.equal(flowARes.bookings[0].salesOrderId, `SO-PO-${fullDraft.booking.preorderId}`);
  assert.equal(flowARes.bookings[0].salesInvoiceId, `INV-SO-PO-${fullDraft.booking.preorderId}`);

  const flowASalesOrder = store.sales_orders[`SO-PO-${fullDraft.booking.preorderId}`];
  assert.ok(flowASalesOrder);
  assert.equal(flowASalesOrder.deliveryStatus, 'PRE-ORDER');
  assert.equal(flowASalesOrder.paymentStatus, 'Paid');
  assert.equal(flowASalesOrder.totalValue, 1699.00);
  assert.equal(flowASalesOrder.preorderId, fullDraft.booking.preorderId);
  assert.equal(store.products['prod-plum-1699'].stock, 49);

  // ---------------------------------------------------------------------------
  // FLOW B: Partial advance ₹169.90 on ₹1,699.00 at initial booking
  // ---------------------------------------------------------------------------
  const partialDraft = await service.createPreorder({
    userId: 'cust-1',
    customerId: 'cust-1',
    customerDisplayName: 'Swapna',
    productId: 'prod-plum-1699',
    quantity: 1,
    paymentType: 'partial',
    bookingAdvance: 169.90,
    giftWrap: false,
    specialSuggestion: '',
    expectedDeliveryDate: '2026-12-09',
    preferredCourierAgent: 'DTDC',
    idempotencyKey: 'idem_flow_b_169_90',
  });

  const flowBRes = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: 'CHK-FLOW-B-1',
    paymentReference: 'pay_flow_b_169_90',
    userId: 'cust-1',
    customerId: 'cust-1',
    customerDisplayName: 'Swapna',
    regularSalesOrderId: null,
    regularSalesAmount: 0,
    preorderIds: [partialDraft.booking.preorderId],
    preorderItemOverrides: [
      {
        preorderId: partialDraft.booking.preorderId,
        productId: 'prod-plum-1699',
        quantity: 1,
        paymentType: 'partial',
        bookingAdvance: 169.90,
        expectedDeliveryDate: '2026-12-09',
        preferredCourierAgent: 'DTDC',
        idempotencyKey: 'idem_flow_b_169_90',
      },
    ],
  });

  assert.equal(flowBRes.bookings.length, 1);
  assert.equal(flowBRes.bookings[0].paymentStatus, 'partially_paid');
  assert.equal(flowBRes.bookings[0].initialBookingAdvance, 169.90);
  assert.equal(flowBRes.bookings[0].totalVerifiedPaid, 169.90);
  assert.equal(flowBRes.bookings[0].remainingBalance, 1529.10);
  assert.equal(flowBRes.bookings[0].conversionStatus, 'not_applicable');
  assert.equal(flowBRes.bookings[0].salesOrderId, null);
  // No sales order created for Flow B, stock unchanged at 49
  assert.equal(store.sales_orders[`SO-PO-${partialDraft.booking.preorderId}`], undefined);
  assert.equal(store.products['prod-plum-1699'].stock, 49);

  // ---------------------------------------------------------------------------
  // FLOW C: Later Pay Remaining Balance (₹1,529.10) -> Quote, Checkout, Settlement & Conversion
  // ---------------------------------------------------------------------------
  const quote = await service.getPreorderBalanceQuote({
    preorderId: partialDraft.booking.preorderId,
    requesterUid: 'cust-1',
    isAdmin: false,
  });
  assert.equal(quote.totalProductValue, 1699.00);
  assert.equal(quote.initialBookingAdvance, 169.90);
  assert.equal(quote.totalVerifiedPaid, 169.90);
  assert.equal(quote.remainingBalance, 1529.10);
  assert.equal(quote.canPayBalance, true);

  // Unauthorized user cannot request balance checkout
  await assert.rejects(
    () =>
      service.createPreorderBalanceCheckout({
        preorderId: partialDraft.booking.preorderId,
        requesterUid: 'other-user-999',
      }),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'FORBIDDEN'
  );

  const balanceCheckout = await service.createPreorderBalanceCheckout({
    preorderId: partialDraft.booking.preorderId,
    requesterUid: 'cust-1',
  });
  assert.equal(balanceCheckout.payableAmount, 1529.10);
  assert.equal(balanceCheckout.remainingBalance, 1529.10);
  assert.equal(balanceCheckout.orderData.products[0].isPreorderBalancePayment, true);

  // Simulate downstream invoice failure once during Flow C conversion to verify Admin Reconciliation recovery
  failDownstreamInvoiceOnce = true;

  const flowCRes = await service.confirmPreorderPaymentsForCheckout({
    checkoutReference: balanceCheckout.checkoutId,
    paymentReference: 'pay_flow_c_1529_10',
    userId: 'cust-1',
    customerId: 'cust-1',
    customerDisplayName: 'Swapna',
    regularSalesOrderId: null,
    regularSalesAmount: 0,
    preorderIds: [partialDraft.booking.preorderId],
    preorderItemOverrides: [
      {
        preorderId: partialDraft.booking.preorderId,
        bookingAdvance: 1529.10,
        isBalancePayment: true,
      },
    ],
  });

  // Payment is verified & recorded, sales_orders record created with deliveryStatus = 'PRE-ORDER',
  // and conversionStatus is marked 'failed' because downstream invoice hook threw
  assert.equal(flowCRes.bookings[0].paymentStatus, 'paid');
  assert.equal(flowCRes.bookings[0].initialBookingAdvance, 169.90);
  assert.equal(flowCRes.bookings[0].totalVerifiedPaid, 1699.00);
  assert.equal(flowCRes.bookings[0].remainingBalance, 0);
  assert.equal(flowCRes.bookings[0].conversionStatus, 'failed');
  assert.equal(flowCRes.bookings[0].conversionErrorCode, 'Simulated downstream invoice service outage');
  assert.ok(store.sales_orders[`SO-PO-${partialDraft.booking.preorderId}`]);
  assert.equal(store.sales_orders[`SO-PO-${partialDraft.booking.preorderId}`].deliveryStatus, 'PRE-ORDER');
  assert.equal(store.products['prod-plum-1699'].stock, 48);

  // Admin reconciliation repairs the conversion and links the invoice without double-charging or double-deducting stock
  const reconciled = await service.reconcilePreorderConversion({
    preorderId: partialDraft.booking.preorderId,
    adminUid: 'admin-1',
  });
  assert.equal(reconciled.preorder.conversionStatus, 'converted');
  assert.equal(reconciled.salesOrderId, `SO-PO-${partialDraft.booking.preorderId}`);
  assert.equal(reconciled.preorder.salesInvoiceId, `INV-SO-PO-${partialDraft.booking.preorderId}`);
  assert.equal(store.products['prod-plum-1699'].stock, 48); // stock NOT deducted a second time

  // Subsequent balance checkout attempt on converted booking is rejected
  await assert.rejects(
    () =>
      service.createPreorderBalanceCheckout({
        preorderId: partialDraft.booking.preorderId,
        requesterUid: 'cust-1',
      }),
    (err: unknown) => err instanceof PreorderDomainError && err.code === 'CONFLICT'
  );
});
