Future<Map<String, dynamic>?> launchPlatformCashfreeCheckout({
  required String paymentSessionId,
  required String environment,
  required String transactionId,
  required String returnUrl,
}) async {
  throw UnsupportedError('Web Cashfree checkout is only available on Web.');
}

Future<Map<String, dynamic>?> launchPlatformPayUCheckout({
  required String actionUrl,
  required Map<String, String> fields,
  required String transactionId,
}) async {
  throw UnsupportedError('Web PayU checkout is only available on Web.');
}

Future<Map<String, dynamic>?> launchPlatformPhonePeCheckout({
  required String redirectUrl,
  required String transactionId,
}) async {
  throw UnsupportedError('Web PhonePe checkout is only available on Web.');
}
