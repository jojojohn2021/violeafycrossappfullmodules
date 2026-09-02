import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../presentation/razorpay_checkout_screen.dart';
import 'payment_types.dart';
import 'razorpay_checkout_helper.dart';

export 'payment_types.dart';

/// Server-Authoritative Razorpay Payment Orchestrator.
///
/// 1. Requests Razorpay payment order creation from VioleafyCross backend.
/// 2. Launches Razorpay Checkout Interface (Web JS Modal on Web, WebView Screen on Mobile).
/// 3. Sends payment signature and identifiers to server for authoritative verification.
class PaymentOrchestrator {
  final ApiClient _apiClient;

  PaymentOrchestrator({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<PaymentResult> pay({
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
    return PaymentResult(outcome: outcome, transactionId: txnid);
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
}
