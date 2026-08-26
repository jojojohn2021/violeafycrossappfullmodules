import 'dart:async';
import 'package:flutter/services.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';
import '../../../core/network/api_client.dart';
import 'payment_types.dart';

/// Mobile (Android/iOS) native PayU Flutter SDK integration.
///
/// The hash is precomputed server-side by the existing `/api/payment/initiate`
/// endpoint (identical formula used for Web Redirect) and simply echoed back to
/// the SDK's `generateHash` callback - the merchant salt never reaches the client.
class NativePayUPaymentStrategy {
  static Future<PaymentResult> pay({
    required Map<String, dynamic> txn,
    required ApiClient apiClient,
  }) async {
    final txnData = txn['transaction'] is Map ? Map<String, dynamic>.from(txn['transaction'] as Map) : <String, dynamic>{};
    final payuRequest = txnData['payuRequest'] is Map ? Map<String, dynamic>.from(txnData['payuRequest'] as Map) : <String, dynamic>{};
    final txnid = (txn['txnid'] ?? payuRequest['txnid'])?.toString() ?? '';
    final precomputedHash = (txn['hash'] ?? payuRequest['hash'])?.toString() ?? '';
    final environment = (txnData['environment'] ?? 'Test').toString();

    if (txnid.isEmpty || precomputedHash.isEmpty) {
      return const PaymentResult(
        outcome: PaymentOutcome.initFailed,
        message: 'Missing transaction data required to start the native SDK.',
      );
    }

    final completer = Completer<PaymentResult>();
    var checkoutScreenOpened = false;

    final delegate = _PayUDelegate(
      precomputedHash: precomputedHash,
      transactionId: txnid,
      onResult: (result) {
        if (!completer.isCompleted) completer.complete(result);
      },
    );

    try {
      final checkoutPro = PayUCheckoutProFlutter(delegate);
      delegate.checkoutPro = checkoutPro;

      final payUPaymentParams = <String, dynamic>{
        'key': txn['key'] ?? payuRequest['key'],
        'txnid': txnid,
        'amount': (txn['amount'] ?? payuRequest['amount'])?.toString(),
        'productinfo': txn['productInfo'] ?? payuRequest['productinfo'],
        'firstname': txn['firstname'] ?? payuRequest['firstname'],
        'email': txn['email'] ?? payuRequest['email'],
        'phone': (txn['phone'] ?? payuRequest['phone'] ?? (txnData['orderPayload'] is Map ? txnData['orderPayload']['customerMobile'] : '') ?? '').toString().replaceAll(RegExp(r'\D'), ''),
        'address1': (payuRequest['address1'] ?? '').toString(),
        'surl': payuRequest['surl'],
        'furl': payuRequest['furl'],
      };

      if (payuRequest['udf1']?.toString().trim().isNotEmpty == true) {
        payUPaymentParams['udf1'] = payuRequest['udf1'];
      }
      if (payuRequest['udf2']?.toString().trim().isNotEmpty == true) {
        payUPaymentParams['udf2'] = payuRequest['udf2'];
      }
      if (payuRequest['udf3']?.toString().trim().isNotEmpty == true) {
        payUPaymentParams['udf3'] = payuRequest['udf3'];
      }
      if (payuRequest['udf4']?.toString().trim().isNotEmpty == true) {
        payUPaymentParams['udf4'] = payuRequest['udf4'];
      }
      if (payuRequest['udf5']?.toString().trim().isNotEmpty == true) {
        payUPaymentParams['udf5'] = payuRequest['udf5'];
      }

      final payUCheckoutProConfig = <String, dynamic>{
        'isTestMode': environment != 'Production',
        'merchantResponseTimeoutInSecs': 30,
        'autoSelectOtp': true,
      };

      checkoutScreenOpened = true;
      unawaited(checkoutPro.openCheckoutScreen(
        payUPaymentParams: payUPaymentParams,
        payUCheckoutProConfig: payUCheckoutProConfig,
      ));
    } on MissingPluginException catch (e) {
      return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid, message: 'Native plugin unavailable: $e');
    } on PlatformException catch (e) {
      return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid, message: 'Native SDK platform error: ${e.message}');
    } on UnsupportedError catch (e) {
      return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid, message: 'Native SDK unsupported on this platform: $e');
    } catch (e) {
      // Nothing was submitted to PayU yet - safe to classify as a technical init failure.
      if (!checkoutScreenOpened) {
        return PaymentResult(outcome: PaymentOutcome.initFailed, transactionId: txnid, message: 'Native SDK failed to initialize: $e');
      }
      rethrow;
    }

    try {
      return await completer.future.timeout(const Duration(minutes: 10));
    } on TimeoutException {
      // The transaction may already have been submitted - do not fallback automatically,
      // the backend PayU verification remains the source of truth for reconciliation.
      return PaymentResult(
        outcome: PaymentOutcome.failed,
        transactionId: txnid,
        message: 'Native SDK response timed out; reconcile via server verification.',
      );
    }
  }
}

class _PayUDelegate implements PayUCheckoutProProtocol {
  final String precomputedHash;
  final String transactionId;
  final void Function(PaymentResult) onResult;
  PayUCheckoutProFlutter? checkoutPro;

  _PayUDelegate({
    required this.precomputedHash,
    required this.transactionId,
    required this.onResult,
  });

  @override
  generateHash(Map response) {
    final hashResult = <String, String>{};
    for (final key in response.keys) {
      final keyName = key.toString();
      if (keyName == 'paymentHash') {
        hashResult[keyName] = precomputedHash;
      } else {
        hashResult[keyName] = '';
      }
    }
    checkoutPro?.hashGenerated(hash: hashResult);
  }

  @override
  onPaymentSuccess(dynamic response) {
    onResult(PaymentResult(outcome: PaymentOutcome.success, transactionId: transactionId));
  }

  @override
  onPaymentFailure(dynamic response) {
    onResult(PaymentResult(outcome: PaymentOutcome.failed, transactionId: transactionId));
  }

  @override
  onPaymentCancel(Map? response) {
    onResult(PaymentResult(outcome: PaymentOutcome.cancelled, transactionId: transactionId));
  }

  @override
  onError(Map? response) {
    // Surfaced after the checkout screen was already shown to the user - treat as a
    // real (uncertain) payment outcome, never as a technical init failure.
    onResult(PaymentResult(outcome: PaymentOutcome.failed, transactionId: transactionId));
  }
}
