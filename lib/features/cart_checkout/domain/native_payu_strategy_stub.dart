import '../../../core/network/api_client.dart';
import 'payment_types.dart';

/// Web-safe fallback used whenever `dart:io` is unavailable (Flutter Web).
/// The native PayU Flutter SDK has no web implementation, so this strategy
/// always reports a technical initialization failure - never a payment failure -
/// which lets the orchestrator safely use Web Redirect Flow instead.
class NativePayUPaymentStrategy {
  static Future<PaymentResult> pay({
    required Map<String, dynamic> txn,
    required ApiClient apiClient,
  }) async {
    return const PaymentResult(
      outcome: PaymentOutcome.initFailed,
      message: 'Native PayU Flutter SDK is not available on this platform (Web).',
    );
  }
}
