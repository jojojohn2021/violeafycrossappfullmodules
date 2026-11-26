// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'payment_types.dart';

PaymentOutcome _mapOutcome(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'success':
      return PaymentOutcome.success;
    case 'pending':
      return PaymentOutcome.pending;
    case 'cancelled':
      return PaymentOutcome.cancelled;
    default:
      return PaymentOutcome.failed;
  }
}

Future<Map<String, dynamic>?> launchPlatformCashfreeCheckout({
  required String paymentSessionId,
  required String environment,
  required String transactionId,
  required String returnUrl,
}) {
  final completer = Completer<Map<String, dynamic>?>();
  final callbackName = 'cf_callback_${DateTime.now().millisecondsSinceEpoch}';

  late html.EventListener listener;
  listener = (html.Event event) {
    if (event is html.CustomEvent && event.detail != null) {
      Map<String, dynamic> data = <String, dynamic>{};
      final rawDetail = event.detail;
      if (rawDetail is String) {
        final decoded = jsonDecode(rawDetail);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } else if (rawDetail is Map) {
        data = Map<String, dynamic>.from(rawDetail);
      }
      html.window.removeEventListener(callbackName, listener);
      if (!completer.isCompleted) {
        completer.complete({
          'outcome': _mapOutcome(data['outcome']?.toString()),
          'message': data['message']?.toString(),
        });
      }
    }
  };

  html.window.addEventListener(callbackName, listener);

  try {
    html.window.dispatchEvent(html.CustomEvent('OPEN_CASHFREE_CHECKOUT', detail: {
      'paymentSessionId': paymentSessionId,
      'mode': environment.toLowerCase() == 'production' ? 'production' : 'sandbox',
      'returnUrl': returnUrl,
      'callbackName': callbackName,
    }));
  } catch (e) {
    debugPrint('[Cashfree Web] Exception launching Web checkout: $e');
    html.window.removeEventListener(callbackName, listener);
    if (!completer.isCompleted) {
      completer.complete({'outcome': PaymentOutcome.failed, 'message': e.toString()});
    }
  }

  return completer.future;
}

Future<Map<String, dynamic>?> _awaitPopupCompletion({
  required html.WindowBase popup,
  required String provider,
  required String transactionId,
}) {
  final completer = Completer<Map<String, dynamic>?>();
  Timer? pollTimer;

  late StreamSubscription<html.MessageEvent> sub;
  sub = html.window.onMessage.listen((event) {
    final data = event.data;
    if (data is Map && data['type'] == 'LEAFYMART_GATEWAY_CALLBACK') {
      if (data['provider']?.toString() != provider) return;
      final cbTxn = data['txnid']?.toString() ?? '';
      if (cbTxn.isNotEmpty && cbTxn != transactionId) return;
      pollTimer?.cancel();
      sub.cancel();
      if (!completer.isCompleted) {
        completer.complete({
          'outcome': _mapOutcome(data['status']?.toString()),
          'message': data['message']?.toString(),
        });
      }
    }
  });

  pollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
    if (popup.closed == true) {
      timer.cancel();
      sub.cancel();
      if (!completer.isCompleted) {
        // Popup closed: let backend S2S verify determine final paid/pending/cancelled status.
        completer.complete({'outcome': PaymentOutcome.pending});
      }
    }
  });

  return completer.future;
}

Future<Map<String, dynamic>?> launchPlatformPayUCheckout({
  required String actionUrl,
  required Map<String, String> fields,
  required String transactionId,
}) async {
  final popupName = 'payu_checkout_${DateTime.now().millisecondsSinceEpoch}';
  final popup = html.window.open('', popupName, 'width=520,height=720,scrollbars=yes,resizable=yes');

  final form = html.FormElement()
    ..method = 'POST'
    ..action = actionUrl
    ..target = popupName
    ..style.display = 'none';

  fields.forEach((key, value) {
    final input = html.InputElement()
      ..type = 'hidden'
      ..name = key
      ..value = value;
    form.children.add(input);
  });

  html.document.body?.append(form);
  form.submit();
  form.remove();

  return _awaitPopupCompletion(
    popup: popup,
    provider: 'payu',
    transactionId: transactionId,
  );
}

Future<Map<String, dynamic>?> launchPlatformPhonePeCheckout({
  required String redirectUrl,
  required String transactionId,
}) async {
  final popupName = 'phonepe_checkout_${DateTime.now().millisecondsSinceEpoch}';
  final popup = html.window.open(
    redirectUrl,
    popupName,
    'width=520,height=720,scrollbars=yes,resizable=yes',
  );

  return _awaitPopupCompletion(
    popup: popup,
    provider: 'phonepe',
    transactionId: transactionId,
  );
}
