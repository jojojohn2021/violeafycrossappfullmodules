import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/features/cart_checkout/domain/payment_orchestrator.dart';

void main() {
  tearDown(() {
    PaymentGatewayManager.instance.resetForTesting();
  });

  group('PaymentGatewayManager startup resolution rules', () {
    test('normalizes whitespace and casing for all four supported providers', () {
      expect(
        PaymentGatewayManager.resolveFromServerValue('  RazorPay \n').provider,
        PaymentGatewayProvider.razorpay,
      );
      expect(
        PaymentGatewayManager.resolveFromServerValue(' CASHFREE ').provider,
        PaymentGatewayProvider.cashfree,
      );
      expect(
        PaymentGatewayManager.resolveFromServerValue('PayU').provider,
        PaymentGatewayProvider.payu,
      );
      expect(
        PaymentGatewayManager.resolveFromServerValue('  PhonePe  ').provider,
        PaymentGatewayProvider.phonepe,
      );
    });

    test('defaults to razorpay ONLY after confirmed server response with missing/empty field', () {
      final fromNull = PaymentGatewayManager.resolveFromServerValue(null);
      expect(fromNull.status, PaymentGatewayConfigStatus.ready);
      expect(fromNull.provider, PaymentGatewayProvider.razorpay);
      expect(fromNull.isOnlinePaymentAvailable, isTrue);

      final fromEmpty = PaymentGatewayManager.resolveFromServerValue('   ');
      expect(fromEmpty.status, PaymentGatewayConfigStatus.ready);
      expect(fromEmpty.provider, PaymentGatewayProvider.razorpay);
      expect(fromEmpty.isOnlinePaymentAvailable, isTrue);
    });

    test('disables online payment on unsupported provider value without switching gateways', () {
      final state = PaymentGatewayManager.resolveFromServerValue('stripe');
      expect(state.status, PaymentGatewayConfigStatus.unsupportedProvider);
      expect(state.provider, isNull);
      expect(state.isOnlinePaymentAvailable, isFalse);
      expect(state.errorMessage, contains('stripe'));
    });

    test('serverUnavailable disables online payment and never falls back to razorpay', () {
      const state = PaymentGatewaySessionState.serverUnavailable();
      expect(state.status, PaymentGatewayConfigStatus.serverUnavailable);
      expect(state.provider, isNull);
      expect(state.isOnlinePaymentAvailable, isFalse);
    });

    test('PaymentOrchestrator blocks checkout when startup state is unavailable or unsupported', () async {
      final orchestrator = PaymentOrchestrator();

      PaymentGatewayManager.instance.setStateForTesting(
        const PaymentGatewaySessionState.serverUnavailable(),
      );
      final offlineResult = await orchestrator.pay(orderData: {'id': 'ORD-OFFLINE-1'});
      expect(offlineResult.outcome, PaymentOutcome.initFailed);

      PaymentGatewayManager.instance.setStateForTesting(
        const PaymentGatewaySessionState.unsupportedProvider('unknown_pg'),
      );
      final unsupportedResult = await orchestrator.pay(orderData: {'id': 'ORD-UNSUPPORTED-1'});
      expect(unsupportedResult.outcome, PaymentOutcome.initFailed);
      expect(unsupportedResult.message, contains('unknown_pg'));
    });

    test('enforces strict server-only read and zero persistent storage caching in payment_gateway_config.dart', () {
      final codeOnly = File('lib/features/cart_checkout/domain/payment_gateway_config.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeOnly, contains('Source.server'));
      expect(codeOnly, contains("globalCollection = 'global'"));
      expect(codeOnly, contains("globalConfigDocId = 'config'"));
      expect(codeOnly, contains("providerField = 'epaymentprovider'"));
      expect(codeOnly, isNot(contains('SharedPreferences')));
      expect(codeOnly, isNot(contains('localStorage')));
      expect(codeOnly, isNot(contains('sessionStorage')));
      expect(codeOnly, isNot(contains('Hive')));
      expect(codeOnly, isNot(contains('sqflite')));
    });
  });
}
