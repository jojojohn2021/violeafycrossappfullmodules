import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/env_config.dart';
import '../../../core/network/api_client.dart';
import '../presentation/payu_webview_screen.dart';
import 'payment_types.dart';

export 'payment_types.dart';

/// Centralized payment orchestration abstraction.
///
/// Creates a transaction against the server-configured PayU gateway (Test or Production)
/// and launches PayU Hosted Checkout using in-app WebView on mobile or web redirect on Flutter Web.
class PaymentOrchestrator {
  final ApiClient _apiClient;

  PaymentOrchestrator({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<PaymentResult> pay({
    required Map<String, dynamic> orderData,
    String environment = 'Test',
    BuildContext? context,
  }) async {
    debugPrint('[PaymentOrchestrator] Starting payment with server-configured PayU gateway ($environment).');
    final txn = await _initiate(orderData, environment);
    final txnid = txn['txnid'].toString();

    if (kIsWeb) {
      return WebRedirectPaymentStrategy.launch(txnid);
    }

    if (context != null && context.mounted) {
      final res = await PayUWebViewScreen.start(context, txnid);
      return res ?? PaymentResult(outcome: PaymentOutcome.cancelled, transactionId: txnid);
    }

    return WebRedirectPaymentStrategy.launch(txnid);
  }

  Future<Map<String, dynamic>> _initiate(Map<String, dynamic> orderData, String environment) async {
    final response = await _apiClient.post('/api/payment/initiate', {
      'orderData': orderData,
      'paymentMethod': 'UPI',
      'gateway': 'PayU',
      'environment': environment,
    });
    if (response is! Map) {
      throw Exception('Payment transaction was not created.');
    }
    final result = Map<String, dynamic>.from(response);
    final txnid = result['txnid']?.toString();
    if (txnid == null || txnid.isEmpty) {
      throw Exception('Payment transaction was not created.');
    }
    return result;
  }
}

/// Reuses the existing PayU hosted web-redirect checkout flow unchanged.
class WebRedirectPaymentStrategy {
  static Future<PaymentResult> launch(String transactionId) async {
    final launched = await launchUrl(
      Uri.parse('${EnvConfig.baseUrl}/api/payment/redirect?transactionId=$transactionId'),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw Exception('Unable to open PayU payment.');
    }
    // Result is determined later out-of-app; PayU's callback redirects back into
    // the existing /payment-result route once the server verifies the transaction.
    return PaymentResult(outcome: PaymentOutcome.launchedExternally, transactionId: transactionId);
  }
}

