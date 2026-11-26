import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../presentation/hosted_gateway_checkout_screen.dart';
import '../presentation/razorpay_checkout_screen.dart';
import 'multi_gateway_checkout_helper.dart';
import 'payment_gateway_config.dart';
import 'payment_types.dart';
import 'razorpay_checkout_helper.dart';

export 'payment_gateway_config.dart';
export 'payment_types.dart';

/// Server-Authoritative Multi-Gateway Payment Orchestrator.
///
/// Routes online payments strictly using the active session provider initialized
/// at startup by [PaymentGatewayManager] (`global/config.epaymentprovider`).
/// Preserves the existing Razorpay flow and Cash on Delivery flow unchanged.
class PaymentOrchestrator {
  final ApiClient _apiClient;
  final PaymentGatewayManager _gatewayManager;

  PaymentOrchestrator({
    ApiClient? apiClient,
    PaymentGatewayManager? gatewayManager,
  })  : _apiClient = apiClient ?? ApiClient(),
        _gatewayManager = gatewayManager ?? PaymentGatewayManager.instance;

  Future<PaymentResult> pay({
    required Map<String, dynamic> orderData,
    String environment = 'Live',
    BuildContext? context,
  }) async {
    final sessionState = _gatewayManager.state;
    if (!sessionState.isOnlinePaymentAvailable || sessionState.provider == null) {
      debugPrint(
        '[PaymentOrchestrator] Online payment blocked: ${sessionState.errorMessage}',
      );
      return PaymentResult(
        outcome: PaymentOutcome.initFailed,
        message: sessionState.errorMessage ??
            'Online payment is currently unavailable. Please try again later.',
      );
    }

    final provider = sessionState.provider!;
    debugPrint(
      '[PaymentOrchestrator] Routing checkout using startup session provider: ${provider.code}',
    );

    switch (provider) {
      case PaymentGatewayProvider.razorpay:
        return _payWithRazorpay(
          orderData: orderData,
          environment: environment,
          context: context,
        );
      case PaymentGatewayProvider.cashfree:
        return _payWithCashfree(
          orderData: orderData,
          context: context,
        );
      case PaymentGatewayProvider.payu:
        return _payWithPayU(
          orderData: orderData,
          context: context,
        );
      case PaymentGatewayProvider.phonepe:
        return _payWithPhonePe(
          orderData: orderData,
          context: context,
        );
    }
  }

  /// Existing Razorpay flow — preserved without behavioral changes.
  Future<PaymentResult> _payWithRazorpay({
    required Map<String, dynamic> orderData,
    String environment = 'Live',
    BuildContext? context,
  }) async {
    debugPrint('[PaymentOrchestrator] Requesting Razorpay order creation from server ($environment).');

    final orderRes = await _apiClient.post('/api/payment/razorpay/create-order', {
      'orderData': orderData,
      'environment': environment,
    });

    if (orderRes is! Map || orderRes['success'] != true) {
      throw Exception('Failed to create payment order on server.');
    }

    final orderId = orderRes['orderId']?.toString() ?? '';
    final keyId = orderRes['keyId']?.toString() ?? '';
    final amount = (orderRes['amount'] as num?)?.toInt() ?? 0;
    final currency = orderRes['currency']?.toString() ?? 'INR';
    final txnid = orderRes['txnid']?.toString() ?? orderData['id']?.toString() ?? '';

    Map<String, dynamic>? callbackData;

    if (kIsWeb) {
      callbackData = await launchPlatformRazorpayCheckout(
        orderId: orderId,
        keyId: keyId,
        amount: amount,
        currency: currency,
        transactionId: txnid,
        customerName: (orderData['customerName'] ?? 'Customer').toString(),
        customerEmail: (orderData['customerEmail'] ?? '').toString(),
        customerMobile: (orderData['customerMobile'] ?? '').toString(),
      );
    } else if (context != null && context.mounted) {
      callbackData = await RazorpayCheckoutScreen.start(
        context,
        orderId: orderId,
        keyId: keyId,
        amount: amount,
        currency: currency,
        transactionId: txnid,
        customerName: (orderData['customerName'] ?? 'Customer').toString(),
        customerEmail: (orderData['customerEmail'] ?? '').toString(),
        customerMobile: (orderData['customerMobile'] ?? '').toString(),
      );
    }

    if (callbackData != null && callbackData['outcome'] == PaymentOutcome.success) {
      return await verifyRazorpayPayment(
        transactionId: txnid,
        razorpayOrderId: callbackData['razorpay_order_id']?.toString() ?? orderId,
        razorpayPaymentId: callbackData['razorpay_payment_id']?.toString() ?? '',
        razorpaySignature: callbackData['razorpay_signature']?.toString() ?? '',
      );
    }

    final outcome = (callbackData?['outcome'] as PaymentOutcome?) ?? PaymentOutcome.cancelled;
    try {
      await _apiClient.post('/api/payment/razorpay/outcome', {
        'transactionId': txnid,
        'razorpay_order_id': orderId,
        'razorpay_payment_id': callbackData?['razorpay_payment_id']?.toString(),
        'outcome': outcome == PaymentOutcome.cancelled ? 'cancelled' : 'failed',
        'reason': callbackData?['error']?.toString() ??
            callbackData?['reason']?.toString() ??
            (outcome == PaymentOutcome.cancelled
                ? 'Payment cancelled by customer during checkout.'
                : 'Payment failed during checkout.'),
      });
    } catch (e) {
      debugPrint('[PaymentOrchestrator] Outcome reporting warning: $e');
    }
    return PaymentResult(outcome: outcome, transactionId: txnid);
  }

  /// Cashfree official checkout flow (Web JS SDK v3 modal + Android/iOS WebView + S2S verify).
  Future<PaymentResult> _payWithCashfree({
    required Map<String, dynamic> orderData,
    BuildContext? context,
  }) async {
    final orderRes = await _apiClient.post('/api/payment/cashfree/create-order', {
      'orderData': orderData,
    });

    if (orderRes is! Map || orderRes['success'] != true) {
      final errMsg = (orderRes is Map ? orderRes['error'] : null)?.toString() ??
          'Failed to create Cashfree payment session on server.';
      throw Exception(errMsg);
    }

    final txnid = orderRes['txnid']?.toString() ?? orderData['id']?.toString() ?? '';
    final paymentSessionId = orderRes['paymentSessionId']?.toString() ?? '';
    final env = orderRes['environment']?.toString() ?? 'sandbox';
    final returnUrl = orderRes['returnUrl']?.toString() ?? '';

    Map<String, dynamic>? callbackData;
    if (kIsWeb) {
      callbackData = await launchWebCashfreeCheckout(
        paymentSessionId: paymentSessionId,
        environment: env,
        transactionId: txnid,
        returnUrl: returnUrl,
      );
    } else if (context != null && context.mounted) {
      callbackData = await HostedGatewayCheckoutScreen.startCashfree(
        context,
        paymentSessionId: paymentSessionId,
        environment: env,
        transactionId: txnid,
        returnUrl: returnUrl,
      );
    } else {
      return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid);
    }

    return _finalizeHostedGatewayResult(
      provider: 'cashfree',
      transactionId: txnid,
      callbackData: callbackData,
    );
  }

  /// PayU official hosted checkout flow (server-signed SHA-512 hash + Web popup / Mobile WebView + S2S verify).
  Future<PaymentResult> _payWithPayU({
    required Map<String, dynamic> orderData,
    BuildContext? context,
  }) async {
    final orderRes = await _apiClient.post('/api/payment/payu/create-order', {
      'orderData': orderData,
    });

    if (orderRes is! Map || orderRes['success'] != true) {
      final errMsg = (orderRes is Map ? orderRes['error'] : null)?.toString() ??
          'Failed to initialize PayU payment request on server.';
      throw Exception(errMsg);
    }

    final txnid = orderRes['txnid']?.toString() ?? orderData['id']?.toString() ?? '';
    final actionUrl = orderRes['actionUrl']?.toString() ?? '';
    final rawFields = orderRes['fields'];
    final fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((k, v) => fields[k.toString()] = v?.toString() ?? '');
    }

    Map<String, dynamic>? callbackData;
    if (kIsWeb) {
      callbackData = await launchWebPayUCheckout(
        actionUrl: actionUrl,
        fields: fields,
        transactionId: txnid,
      );
    } else if (context != null && context.mounted) {
      callbackData = await HostedGatewayCheckoutScreen.startPayU(
        context,
        actionUrl: actionUrl,
        fields: fields,
        transactionId: txnid,
      );
    } else {
      return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid);
    }

    return _finalizeHostedGatewayResult(
      provider: 'payu',
      transactionId: txnid,
      callbackData: callbackData,
    );
  }

  /// PhonePe official Standard Checkout flow (server X-VERIFY + Web popup / Mobile WebView + S2S verify).
  Future<PaymentResult> _payWithPhonePe({
    required Map<String, dynamic> orderData,
    BuildContext? context,
  }) async {
    final orderRes = await _apiClient.post('/api/payment/phonepe/create-order', {
      'orderData': orderData,
    });

    if (orderRes is! Map || orderRes['success'] != true) {
      final errMsg = (orderRes is Map ? orderRes['error'] : null)?.toString() ??
          'Failed to initialize PhonePe payment request on server.';
      throw Exception(errMsg);
    }

    final txnid = orderRes['txnid']?.toString() ?? orderData['id']?.toString() ?? '';
    final redirectUrl = orderRes['redirectUrl']?.toString() ?? '';

    Map<String, dynamic>? callbackData;
    if (kIsWeb) {
      callbackData = await launchWebPhonePeCheckout(
        redirectUrl: redirectUrl,
        transactionId: txnid,
      );
    } else if (context != null && context.mounted) {
      callbackData = await HostedGatewayCheckoutScreen.startPhonePe(
        context,
        redirectUrl: redirectUrl,
        transactionId: txnid,
      );
    } else {
      return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid);
    }

    return _finalizeHostedGatewayResult(
      provider: 'phonepe',
      transactionId: txnid,
      callbackData: callbackData,
    );
  }

  /// Authoritative server-side verification for Cashfree, PayU, and PhonePe.
  /// Never marks an order paid from a client callback alone.
  Future<PaymentResult> _finalizeHostedGatewayResult({
    required String provider,
    required String transactionId,
    required Map<String, dynamic>? callbackData,
  }) async {
    final clientOutcome = (callbackData?['outcome'] as PaymentOutcome?) ?? PaymentOutcome.cancelled;

    if (clientOutcome == PaymentOutcome.cancelled) {
      try {
        await _apiClient.post('/api/payment/$provider/outcome', {
          'transactionId': transactionId,
          'outcome': 'cancelled',
          'reason': callbackData?['message']?.toString() ?? 'Payment cancelled by customer during checkout.',
        });
      } catch (e) {
        debugPrint('[PaymentOrchestrator] $provider cancel reporting warning: $e');
      }
      return PaymentResult(outcome: PaymentOutcome.cancelled, transactionId: transactionId);
    }

    try {
      final verifyRes = await _apiClient.post('/api/payment/$provider/verify', {
        'transactionId': transactionId,
      });
      if (verifyRes is Map) {
        final status = (verifyRes['status'] ?? '').toString().toLowerCase();
        if (verifyRes['success'] == true || status == 'success') {
          return PaymentResult(outcome: PaymentOutcome.success, transactionId: transactionId);
        }
        if (status == 'pending') {
          return PaymentResult(outcome: PaymentOutcome.pending, transactionId: transactionId);
        }
        if (status == 'cancelled') {
          return PaymentResult(outcome: PaymentOutcome.cancelled, transactionId: transactionId);
        }
      }
      return PaymentResult(outcome: PaymentOutcome.failed, transactionId: transactionId);
    } catch (e) {
      debugPrint('[PaymentOrchestrator] $provider server verification exception: $e');
      if (clientOutcome == PaymentOutcome.pending) {
        return PaymentResult(outcome: PaymentOutcome.pending, transactionId: transactionId);
      }
      return PaymentResult(outcome: PaymentOutcome.failed, transactionId: transactionId);
    }
  }

  Future<PaymentResult> verifyRazorpayPayment({
    required String transactionId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final response = await _apiClient.post('/api/payment/razorpay/verify', {
        'transactionId': transactionId,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      });

      if (response is Map && response['success'] == true) {
        return PaymentResult(outcome: PaymentOutcome.success, transactionId: transactionId);
      }
      return PaymentResult(outcome: PaymentOutcome.failed, transactionId: transactionId);
    } catch (e) {
      debugPrint('[PaymentOrchestrator] Server Razorpay verification exception: $e');
      return PaymentResult(outcome: PaymentOutcome.failed, transactionId: transactionId);
    }
  }

  /// Server-Authoritative Cash on Delivery (COD) Order Creation (Web Only)
  Future<PaymentResult> payCod({
    required Map<String, dynamic> orderData,
  }) async {
    debugPrint('[PaymentOrchestrator] Submitting Cash on Delivery order request to server.');

    final res = await _apiClient.post('/api/orders/create-cod', {
      'orderData': orderData,
    });

    if (res is Map && res['success'] == true) {
      final txnid = res['orderId']?.toString() ?? orderData['id']?.toString() ?? '';
      return PaymentResult(outcome: PaymentOutcome.success, transactionId: txnid);
    }

    final errorMsg = (res is Map ? res['message'] ?? res['error'] : null)?.toString() ?? 'Failed to create Cash on Delivery order.';
    throw Exception(errorMsg);
  }
}
