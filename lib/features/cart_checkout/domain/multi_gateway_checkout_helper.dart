import 'multi_gateway_checkout_helper_stub.dart'
    if (dart.library.html) 'multi_gateway_checkout_helper_web.dart';

/// Launches Cashfree official JS SDK v3 modal checkout on Web.
Future<Map<String, dynamic>?> launchWebCashfreeCheckout({
  required String paymentSessionId,
  required String environment,
  required String transactionId,
  required String returnUrl,
}) =>
    launchPlatformCashfreeCheckout(
      paymentSessionId: paymentSessionId,
      environment: environment,
      transactionId: transactionId,
      returnUrl: returnUrl,
    );

/// Launches PayU hosted checkout via POST form submission in a Web popup.
Future<Map<String, dynamic>?> launchWebPayUCheckout({
  required String actionUrl,
  required Map<String, String> fields,
  required String transactionId,
}) =>
    launchPlatformPayUCheckout(
      actionUrl: actionUrl,
      fields: fields,
      transactionId: transactionId,
    );

/// Launches PhonePe hosted checkout URL in a Web popup.
Future<Map<String, dynamic>?> launchWebPhonePeCheckout({
  required String redirectUrl,
  required String transactionId,
}) =>
    launchPlatformPhonePeCheckout(
      redirectUrl: redirectUrl,
      transactionId: transactionId,
    );
