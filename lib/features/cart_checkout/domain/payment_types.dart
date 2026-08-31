/// Outcome of a single payment attempt made by a [PaymentStrategy].
///
/// [initFailed] means the payment mechanism could not even start (SDK/plugin
/// unavailable, unsupported platform, platform-channel error) - NO transaction
/// was submitted to gateway, so it is safe to handle initialization errors cleanly.
///
/// [success]/[failed]/[cancelled] mean a real transaction attempt happened -
/// these must never trigger an automatic second payment attempt.
enum PaymentOutcome { launchedExternally, success, failed, cancelled, initFailed }

class PaymentResult {
  final PaymentOutcome outcome;
  final String? transactionId;
  final String? message;

  const PaymentResult({required this.outcome, this.transactionId, this.message});

  bool get isTechnicalInitFailure => outcome == PaymentOutcome.initFailed;
}
