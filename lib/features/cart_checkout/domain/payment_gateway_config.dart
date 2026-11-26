import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config/env_config.dart';

/// Supported online payment gateways configured via Firestore `global/config.epaymentprovider`.
enum PaymentGatewayProvider {
  razorpay('razorpay', 'Razorpay'),
  cashfree('cashfree', 'Cashfree'),
  payu('payu', 'PayU'),
  phonepe('phonepe', 'PhonePe');

  final String code;
  final String displayName;

  const PaymentGatewayProvider(this.code, this.displayName);
}

enum PaymentGatewayConfigStatus {
  uninitialized,
  ready,
  serverUnavailable,
  unsupportedProvider,
}

/// Immutable runtime-only state for the active payment provider selected at startup.
/// Never persisted to SharedPreferences, LocalStorage, SessionStorage, IndexedDB,
/// cookies, Hive, SQLite, or local files.
class PaymentGatewaySessionState {
  final PaymentGatewayConfigStatus status;
  final PaymentGatewayProvider? provider;
  final String? rawValue;
  final String? errorMessage;

  const PaymentGatewaySessionState({
    required this.status,
    this.provider,
    this.rawValue,
    this.errorMessage,
  });

  const PaymentGatewaySessionState.uninitialized()
      : status = PaymentGatewayConfigStatus.uninitialized,
        provider = null,
        rawValue = null,
        errorMessage = 'Payment gateway configuration has not been initialized.';

  const PaymentGatewaySessionState.ready(
    PaymentGatewayProvider activeProvider, {
    this.rawValue,
  })  : status = PaymentGatewayConfigStatus.ready,
        provider = activeProvider,
        errorMessage = null;

  const PaymentGatewaySessionState.serverUnavailable([String? detail])
      : status = PaymentGatewayConfigStatus.serverUnavailable,
        provider = null,
        rawValue = null,
        errorMessage = detail ??
            'Unable to reach payment configuration server. Online payment is temporarily unavailable.';

  const PaymentGatewaySessionState.unsupportedProvider(String invalidValue)
      : status = PaymentGatewayConfigStatus.unsupportedProvider,
        provider = null,
        rawValue = invalidValue,
        errorMessage =
            'Unsupported payment gateway configuration ("$invalidValue"). Online payment is disabled.';

  bool get isOnlinePaymentAvailable =>
      status == PaymentGatewayConfigStatus.ready && provider != null;
}

/// Authoritative startup payment gateway selector.
///
/// STRICT RULES:
/// - Reads `global/config` field `epaymentprovider` directly from Firestore server
///   using `GetOptions(source: Source.server)`.
/// - Never reads from Firestore offline cache or any persistent local storage.
/// - Retains the resolved provider in temporary runtime memory only for the current session.
/// - Does not create payment orders or tokens at startup.
class PaymentGatewayManager {
  PaymentGatewayManager._();

  static final PaymentGatewayManager instance = PaymentGatewayManager._();

  static const String globalCollection = 'global';
  static const String globalConfigDocId = 'config';
  static const String providerField = 'epaymentprovider';

  PaymentGatewaySessionState _state = const PaymentGatewaySessionState.uninitialized();

  PaymentGatewaySessionState get state => _state;
  PaymentGatewayProvider? get activeProvider => _state.provider;
  bool get isOnlinePaymentAvailable => _state.isOnlinePaymentAvailable;

  /// Pure resolver for `epaymentprovider` after a confirmed Firestore server response.
  ///
  /// - Missing or empty value -> defaults to [PaymentGatewayProvider.razorpay] ONLY
  ///   when called after a successful server response.
  /// - Recognized normalized values (`razorpay`, `cashfree`, `payu`, `phonepe`) -> ready.
  /// - Any other value -> [PaymentGatewayConfigStatus.unsupportedProvider] (online payment disabled).
  static PaymentGatewaySessionState resolveFromServerValue(dynamic rawValue) {
    final normalized = rawValue?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return const PaymentGatewaySessionState.ready(
        PaymentGatewayProvider.razorpay,
        rawValue: '',
      );
    }

    switch (normalized) {
      case 'razorpay':
        return PaymentGatewaySessionState.ready(
          PaymentGatewayProvider.razorpay,
          rawValue: normalized,
        );
      case 'cashfree':
        return PaymentGatewaySessionState.ready(
          PaymentGatewayProvider.cashfree,
          rawValue: normalized,
        );
      case 'payu':
        return PaymentGatewaySessionState.ready(
          PaymentGatewayProvider.payu,
          rawValue: normalized,
        );
      case 'phonepe':
        return PaymentGatewaySessionState.ready(
          PaymentGatewayProvider.phonepe,
          rawValue: normalized,
        );
      default:
        return PaymentGatewaySessionState.unsupportedProvider(normalized);
    }
  }

  /// Fetches `global/config` directly from the Firestore server (`Source.server`),
  /// validates `epaymentprovider`, and stores the result in runtime memory only.
  Future<PaymentGatewaySessionState> initializeFromServer({
    FirebaseFirestore? firestore,
  }) async {
    try {
      final db = firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: EnvConfig.firestoreDatabaseId,
          );

      final snapshot = await db
          .collection(globalCollection)
          .doc(globalConfigDocId)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Timed out fetching global/config from Firestore server.',
            ),
          );

      // Defensive guard: reject any snapshot that reports coming from cache.
      if (snapshot.metadata.isFromCache) {
        _state = const PaymentGatewaySessionState.serverUnavailable(
          'Cached payment configuration rejected. Fresh server response required.',
        );
        debugPrint('[PaymentGatewayManager] Rejected cached global/config snapshot.');
        return _state;
      }

      final data = snapshot.data();
      final rawProvider = data?[providerField];
      _state = resolveFromServerValue(rawProvider);

      if (_state.isOnlinePaymentAvailable) {
        debugPrint(
          '[PaymentGatewayManager] Active session payment gateway initialized from server: ${_state.provider!.code}',
        );
      } else {
        debugPrint(
          '[PaymentGatewayManager] Online payment disabled: ${_state.errorMessage}',
        );
      }
      return _state;
    } catch (e) {
      // STRICT: Never fall back to cache, never activate a previous provider,
      // and never automatically fall back to Razorpay when server is unavailable.
      _state = const PaymentGatewaySessionState.serverUnavailable();
      debugPrint(
        '[PaymentGatewayManager] Server-only global/config fetch failed; online payment disabled: $e',
      );
      return _state;
    }
  }

  /// Permits explicit retry after a server-unavailable startup without using cache.
  Future<PaymentGatewaySessionState> retryFromServer({
    FirebaseFirestore? firestore,
  }) {
    return initializeFromServer(firestore: firestore);
  }

  /// Test-only helper to set or reset in-memory session state.
  @visibleForTesting
  void setStateForTesting(PaymentGatewaySessionState nextState) {
    _state = nextState;
  }

  /// Test-only helper to clear in-memory session state (simulates fresh launch/reload).
  @visibleForTesting
  void resetForTesting() {
    _state = const PaymentGatewaySessionState.uninitialized();
  }
}
