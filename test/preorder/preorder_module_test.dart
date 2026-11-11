import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/core/utils/gst_calculator.dart';
import 'package:leafy_webapp/features/preorder/data/models/preorder_models.dart';
import 'package:leafy_webapp/features/preorder/presentation/widgets/preorder_widgets.dart';
import 'package:leafy_webapp/features/preorder/preorder_module.dart';
import 'package:leafy_webapp/models/models.dart';
import 'package:leafy_webapp/providers/app_providers.dart';
import 'package:leafy_webapp/repositories/shopping_repository.dart';

ProductPerformance _buildProduct({required bool preorderactive}) {
  return ProductPerformance(
    id: 'prod-101',
    name: 'Cold-Pressed Almond Oil',
    sku: 'ALM-101',
    packingSize: '250ml',
    unit: 'Bottle',
    onlinePrice: 500,
    shopPrice: 600,
    notes: '',
    unitsSold: 10,
    revenue: 5000,
    growthRate: 1.0,
    stock: 25,
    amazonSales: 0,
    flipkartSales: 0,
    meeshoSales: 0,
    vamjoSales: 0,
    whatsappSales: 0,
    countersaleSales: 0,
    preorderactive: preorderactive,
  );
}

void main() {
  setUp(() {
    ShoppingRepository().clearCart();
  });

  group('ProductPerformance strict preorderactive parsing', () {
    test('parses true only when preorderactive is strictly boolean true', () {
      final base = {
        'id': 'p1',
        'name': 'Test Item',
        'sku': 'SKU1',
        'packingSize': '100g',
        'unit': 'Pack',
        'onlinePrice': 100,
        'shopPrice': 120,
      };

      expect(ProductPerformance.fromJson({...base, 'preorderactive': true}).preorderactive, isTrue);
      expect(ProductPerformance.fromJson({...base, 'preorderactive': false}).preorderactive, isFalse);
      expect(ProductPerformance.fromJson({...base, 'preorderactive': 'true'}).preorderactive, isFalse);
      expect(ProductPerformance.fromJson({...base, 'preorderactive': 1}).preorderactive, isFalse);
      expect(ProductPerformance.fromJson({...base, 'preorderactive': null}).preorderactive, isFalse);
      expect(ProductPerformance.fromJson(base).preorderactive, isFalse);
    });
  });

  group('PreorderAdvanceValidator unit tests (Section 3.1 & 3.3)', () {
    test('Full Amount sets Booking Advance = 100% and Remaining Balance = 0', () {
      final res = PreorderAdvanceValidator.validateAndCalculate(
        onlinePrice: 500,
        quantity: 2,
        paymentOption: PreorderPaymentOption.full,
      );
      expect(res.isValid, isTrue);
      expect(res.totalProductValue, 1000.0);
      expect(res.bookingAdvance, 1000.0);
      expect(res.remainingBalance, 0.0);
      expect(res.minBookingAdvance, 100.0);
    });

    test('Partial Payment validates 10% minimum and 100% maximum boundaries', () {
      // Exact 10% minimum
      final minValid = PreorderAdvanceValidator.validateAndCalculate(
        onlinePrice: 500,
        quantity: 2,
        paymentOption: PreorderPaymentOption.partial,
        partialInputText: '100',
      );
      expect(minValid.isValid, isTrue);
      expect(minValid.bookingAdvance, 100.0);
      expect(minValid.remainingBalance, 900.0);

      // Exact 100% maximum
      final maxValid = PreorderAdvanceValidator.validateAndCalculate(
        onlinePrice: 500,
        quantity: 2,
        paymentOption: PreorderPaymentOption.partial,
        partialInputText: '1000',
      );
      expect(maxValid.isValid, isTrue);
      expect(maxValid.bookingAdvance, 1000.0);
      expect(maxValid.remainingBalance, 0.0);

      // Below 10% rejected
      final belowMin = PreorderAdvanceValidator.validateAndCalculate(
        onlinePrice: 500,
        quantity: 2,
        paymentOption: PreorderPaymentOption.partial,
        partialInputText: '99.50',
      );
      expect(belowMin.isValid, isFalse);

      // Above 100% rejected
      final aboveMax = PreorderAdvanceValidator.validateAndCalculate(
        onlinePrice: 500,
        quantity: 2,
        paymentOption: PreorderPaymentOption.partial,
        partialInputText: '1000.01',
      );
      expect(aboveMax.isValid, isFalse);

      // Zero, negative, or non-numeric rejected
      for (final bad in ['0', '-50', 'abc', '']) {
        final invalid = PreorderAdvanceValidator.validateAndCalculate(
          onlinePrice: 500,
          quantity: 1,
          paymentOption: PreorderPaymentOption.partial,
          partialInputText: bad,
        );
        expect(invalid.isValid, isFalse);
      }
    });

    test('Expected Date of Delivery allows only future dates', () {
      final refNow = DateTime(2026, 11, 10, 14, 30);
      expect(PreorderAdvanceValidator.isFutureDeliveryDate(DateTime(2026, 11, 9), now: refNow), isFalse);
      expect(PreorderAdvanceValidator.isFutureDeliveryDate(DateTime(2026, 11, 10), now: refNow), isFalse);
      expect(PreorderAdvanceValidator.isFutureDeliveryDate(DateTime(2026, 11, 11), now: refNow), isTrue);
    });
  });

  group('PreorderBookingDetailsSection UI & Validation', () {
    testWidgets('hides PreorderBookingDetailsSection when preorderactive is false', (tester) async {
      final product = _buildProduct(preorderactive: false);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PreorderBookingDetailsSection(product: product),
            ),
          ),
        ),
      );

      expect(find.text('Pre-Order Booking Details'), findsNothing);
      expect(find.text('PRE-ORDER BOOKING'), findsNothing);
    });

    testWidgets('renders Pre-Order Booking Details and PRE-ORDER BOOKING button when preorderactive is true',
        (tester) async {
      final product = _buildProduct(preorderactive: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
            preorderCourierAgentsProvider.overrideWith((ref) async => const ['India Post', 'DTDC', 'Delhivery']),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PreorderBookingDetailsSection(product: product),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pre-Order Booking Details'), findsOneWidget);
      expect(find.text('Full Amount'), findsOneWidget);
      expect(find.text('Partial Payment'), findsOneWidget);
      expect(find.text('Gift Wrap'), findsOneWidget);
      expect(find.text('Expected Date of Delivery'), findsOneWidget);
      expect(find.text('Preferred Courier Agent'), findsOneWidget);
      expect(find.text('Amazon Shipping'), findsOneWidget);
      expect(find.text('PRE-ORDER BOOKING'), findsOneWidget);
    });

    testWidgets(
        'switches PRE-ORDER BOOKING button to [- qty +] and View Cart control when item is in cart, updates qty, and restores button on 0',
        (tester) async {
      final product = _buildProduct(preorderactive: true);
      final cartNotifier = CartNotifier(ShoppingRepository());
      cartNotifier.addPreorderToCart(
        SalesProduct(
          productId: product.id,
          productName: product.name,
          quantity: 1,
          price: 500,
          isPreorder: true,
          preorderId: 'PO-2026-100',
          onlinePriceSnapshot: 500,
          totalProductValue: 500,
          paymentType: 'full',
          paymentTypeLabel: 'Full Amount',
          bookingAdvance: 500,
          remainingBalance: 0,
          giftWrap: false,
          specialSuggestion: '',
          expectedDeliveryDate: '2026-12-01',
          preferredCourierAgent: 'India Post',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shoppingRepositoryProvider.overrideWithValue(ShoppingRepository()),
            preorderCourierAgentsProvider.overrideWith((ref) async => const ['India Post', 'DTDC']),
            cartProvider.overrideWith((ref) => cartNotifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PreorderBookingDetailsSection(product: product),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // PRE-ORDER BOOKING button is hidden; [- | 1 | +], View Cart, and PROCEED TO PAY buttons are shown
      expect(find.byKey(ValueKey('preorder_action_${product.id}')), findsNothing);
      expect(find.byKey(ValueKey('preorder_qty_control_${product.id}')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder_view_cart_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder_proceed_to_pay_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('preorder_cart_qty_value')), findsOneWidget);

      // Tap '+' to increase quantity to 2
      await tester.ensureVisible(find.byKey(const ValueKey('preorder_cart_qty_increase')));
      await tester.tap(find.byKey(const ValueKey('preorder_cart_qty_increase')));
      await tester.pumpAndSettle();

      expect(cartNotifier.state.length, 1);
      expect(cartNotifier.state.first.quantity, 2);
      expect(cartNotifier.state.first.totalProductValue, 1000.0);
      expect(cartNotifier.state.first.bookingAdvance, 1000.0);

      // Tap '-' twice to decrease quantity from 2 -> 1 -> 0 (removing item)
      await tester.tap(find.byKey(const ValueKey('preorder_cart_qty_decrease')));
      await tester.pumpAndSettle();
      expect(cartNotifier.state.first.quantity, 1);

      await tester.tap(find.byKey(const ValueKey('preorder_cart_qty_decrease')));
      await tester.pumpAndSettle();

      // Cart is now empty and PRE-ORDER BOOKING button is restored
      expect(cartNotifier.state, isEmpty);
      expect(find.byKey(ValueKey('preorder_action_${product.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('preorder_qty_control_${product.id}')), findsNothing);
    });
  });

  group('CartNotifier & GstCalculator separation of regular and pre-order items', () {
    test('does not allow duplicate pre-order items for the same productId and updates existing item instead', () {
      final notifier = CartNotifier(ShoppingRepository());

      notifier.addPreorderToCart(
        SalesProduct(
          productId: 'prod-101',
          productName: 'Cold-Pressed Almond Oil',
          quantity: 1,
          price: 500,
          isPreorder: true,
          preorderId: 'PO-2026-001',
          onlinePriceSnapshot: 500,
          totalProductValue: 500,
          paymentType: 'partial',
          paymentTypeLabel: 'Partial Payment',
          bookingAdvance: 100,
          remainingBalance: 400,
          giftWrap: false,
          specialSuggestion: '',
          expectedDeliveryDate: '2026-12-01',
          preferredCourierAgent: 'India Post',
        ),
      );
      expect(notifier.state.length, 1);

      // Adding another pre-order item for the same productId replaces/updates rather than duplicating
      notifier.addPreorderToCart(
        SalesProduct(
          productId: 'prod-101',
          productName: 'Cold-Pressed Almond Oil',
          quantity: 2,
          price: 500,
          isPreorder: true,
          preorderId: 'PO-2026-002',
          onlinePriceSnapshot: 500,
          totalProductValue: 1000,
          paymentType: 'partial',
          paymentTypeLabel: 'Partial Payment',
          bookingAdvance: 200,
          remainingBalance: 800,
          giftWrap: true,
          specialSuggestion: 'Updated',
          expectedDeliveryDate: '2026-12-02',
          preferredCourierAgent: 'DTDC',
        ),
      );
      expect(notifier.state.length, 1);
      expect(notifier.state.first.quantity, 2);
      expect(notifier.state.first.bookingAdvance, 200.0);
      expect(notifier.state.first.remainingBalance, 800.0);

      // Updating quantity via updateQuantity scales advance & remaining balance proportionally
      notifier.updateQuantity('prod-101', 3);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.quantity, 3);
      expect(notifier.state.first.totalProductValue, 1500.0);
      expect(notifier.state.first.bookingAdvance, 300.0);
      expect(notifier.state.first.remainingBalance, 1200.0);
    });
    test('CartNotifier blocks preorderactive product from regular addToCart and places regular items before pre-order items', () {
      final notifier = CartNotifier(ShoppingRepository());
      final preorderProduct = _buildProduct(preorderactive: true);
      final regularProduct = _buildProduct(preorderactive: false);

      // Attempting to add pre-order product as regular item is rejected with StateError
      expect(() => notifier.addToCart(preorderProduct), throwsStateError);
      expect(notifier.state, isEmpty);

      // Add a pre-order booking item first
      final preorderItem = SalesProduct(
        productId: preorderProduct.id,
        productName: preorderProduct.name,
        quantity: 2,
        price: 500,
        isPreorder: true,
        preorderId: 'PO-2026-001',
        onlinePriceSnapshot: 500,
        totalProductValue: 1000,
        paymentType: 'partial',
        paymentTypeLabel: 'Partial Payment',
        bookingAdvance: 200,
        remainingBalance: 800,
        giftWrap: true,
        specialSuggestion: 'Handle with care',
        expectedDeliveryDate: '2026-12-01',
        preferredCourierAgent: 'Delhivery',
      );
      notifier.addPreorderToCart(preorderItem);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.isPreorder, isTrue);

      // Add regular item after pre-order item -> regular item must be ordered first
      notifier.addToCart(regularProduct);
      expect(notifier.state.length, 2);
      expect(notifier.state[0].isPreorder, isFalse);
      expect(notifier.state[1].isPreorder, isTrue);

      // Verify GST and totals separation
      final summary = GstCalculator.calculateCartSummary(notifier.state, deliveryFee: 40);
      expect(summary.regularSalesSubtotal, 500.0);
      expect(summary.regularInvoiceGrandTotal, 540.0);
      expect(summary.totalPreorderBookingAdvance, 200.0);
      expect(summary.customerGrandTotalPayable, 740.0);
    });

    test('Pre-order-only cart has zero Regular Invoice Grand Total, zero GST, and Customer Grand Total Payable == Advance', () {
      final notifier = CartNotifier(ShoppingRepository());
      final preorderItem = SalesProduct(
        productId: 'prod-101',
        productName: 'Cold-Pressed Almond Oil',
        quantity: 1,
        price: 500,
        isPreorder: true,
        preorderId: 'PO-2026-002',
        onlinePriceSnapshot: 500,
        totalProductValue: 500,
        paymentType: 'full',
        paymentTypeLabel: 'Full Amount',
        bookingAdvance: 500,
        remainingBalance: 0,
        giftWrap: false,
        specialSuggestion: '',
        expectedDeliveryDate: '2026-12-05',
        preferredCourierAgent: 'India Post',
      );
      notifier.addPreorderToCart(preorderItem);

      final summary = GstCalculator.calculateCartSummary(notifier.state);
      expect(summary.regularSalesSubtotal, 0.0);
      expect(summary.totalTaxableValue, 0.0);
      expect(summary.totalGstAmount, 0.0);
      expect(summary.regularInvoiceGrandTotal, 0.0);
      expect(summary.totalPreorderBookingAdvance, 500.0);
      expect(summary.customerGrandTotalPayable, 500.0);
    });
  });
}
