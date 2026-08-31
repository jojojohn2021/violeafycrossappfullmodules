import 'razorpay_checkout_helper_stub.dart'
    if (dart.library.html) 'razorpay_checkout_helper_web.dart';

Future<Map<String, dynamic>?> launchPlatformRazorpayCheckout({
  required String orderId,
  required String keyId,
  required int amount,
  required String currency,
  required String transactionId,
  required String customerName,
  required String customerEmail,
  required String customerMobile,
}) =>
    launchWebRazorpayCheckout(
      orderId: orderId,
      keyId: keyId,
      amount: amount,
      currency: currency,
      transactionId: transactionId,
      customerName: customerName,
      customerEmail: customerEmail,
      customerMobile: customerMobile,
    );
