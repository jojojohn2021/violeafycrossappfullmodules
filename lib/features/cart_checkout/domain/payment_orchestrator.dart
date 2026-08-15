import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/env_config.dart';
import '../../../core/network/api_client.dart';
import 'payment_types.dart';

export 'payment_types.dart';

/// Centralized payment orchestration abstraction.
///
/// Creates a transaction against the server-configured PayU gateway and opens
/// its hosted checkout page.
class PaymentOrchestrator {
  final ApiClient _apiClient;

  PaymentOrchestrator({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<PaymentResult> pay({
    required Map<String, dynamic> orderData,
  }) async {
    debugPrint('[PaymentOrchestrator] Starting payment with server-configured PayU gateway.');
    final txn = await _initiate(orderData);
    return WebRedirectPaymentStrategy.launch(txn['txnid'].toString());
  }

  Future<Map<String, dynamic>> _initiate(Map<String, dynamic> orderData) async {
    final response = await _apiClient.post('/api/payment/initiate', {
      'orderData': orderData,
      'paymentMethod': 'PayU',
      'gateway': 'PayU',
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
