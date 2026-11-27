import 'package:flutter/foundation.dart';

/// Platform-specific app icon asset paths resolved strictly from `assets/<platform>/`.
class AppIconAssets {
  AppIconAssets._();

  static const String web = 'assets/web/icon-512.png';
  static const String android = 'assets/android/play_store_512.png';
  static const String ios = 'assets/ios/AppIcon@3x.png';

  /// Returns the app icon asset path for the active platform (Web, Android, or iOS).
  static String get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }
}
