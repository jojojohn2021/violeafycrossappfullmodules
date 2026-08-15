/// Conditional platform selection for the native PayU strategy.
/// `dart:io` is unavailable on Flutter Web, so the web-safe stub (always
/// technical-init-failure) is selected there instead of the real SDK wrapper.
library;

export 'native_payu_strategy_stub.dart' if (dart.library.io) 'native_payu_strategy_io.dart';
