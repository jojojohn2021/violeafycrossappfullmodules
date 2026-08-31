// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'payment_types.dart';

Future<Map<String, dynamic>?> launchWebRazorpayCheckout({
  required String orderId,
  required String keyId,
  required int amount,
  required String currency,
  required String transactionId,
  required String customerName,
  required String customerEmail,
  required String customerMobile,
}) {
  final completer = Completer<Map<String, dynamic>?>();
  final callbackName = 'rzp_callback_${DateTime.now().millisecondsSinceEpoch}';

  late html.EventListener listener;
  listener = (html.Event event) {
    if (event is html.CustomEvent && event.detail != null) {
      final data = Map<String, dynamic>.from(event.detail as Map);
      html.window.removeEventListener(callbackName, listener);
      if (!completer.isCompleted) {
        final outcomeStr = data['outcome']?.toString();
        PaymentOutcome outcome = PaymentOutcome.failed;
        if (outcomeStr == 'success') outcome = PaymentOutcome.success;
        if (outcomeStr == 'cancelled') outcome = PaymentOutcome.cancelled;

        completer.complete({
          'outcome': outcome,
          'razorpay_payment_id': data['razorpay_payment_id']?.toString(),
          'razorpay_order_id': data['razorpay_order_id']?.toString(),
          'razorpay_signature': data['razorpay_signature']?.toString(),
        });
      }
    }
  };

  html.window.addEventListener(callbackName, listener);

  final options = {
    'key': keyId,
    'amount': amount,
    'currency': currency,
    'name': 'VioleafyCross',
    'description': 'Order Payment $transactionId',
    'order_id': orderId,
    'prefill': {
      'name': customerName,
      'email': customerEmail,
      'contact': customerMobile,
    },
    'theme': {
      'color': '#2D6A4F',
    },
  };

  try {
    html.window.dispatchEvent(html.CustomEvent('OPEN_RAZORPAY_CHECKOUT', detail: {
      'options': jsonEncode(options),
      'callbackName': callbackName,
    }));
  } catch (e) {
    debugPrint('[Razorpay Web] Exception launching Web checkout: $e');
    html.window.removeEventListener(callbackName, listener);
    if (!completer.isCompleted) {
      completer.complete({'outcome': PaymentOutcome.failed});
    }
  }

  return completer.future;
}
