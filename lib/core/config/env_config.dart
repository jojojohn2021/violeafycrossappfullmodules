import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnvConfig {
  static const String _defaultDevBaseUrl = 'http://localhost:3000';
  static const String _defaultAndroidEmulatorBaseUrl = 'http://10.0.2.2:3000';
  static const String _defaultProductionBaseUrl = 'https://www.vamjo.com'; // Fallback
  
  static String _currentBaseUrl = '';

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('custom_api_base_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _currentBaseUrl = savedUrl;
      return;
    }

    if (kIsWeb) {
      // In web browser, we default to the current host origin.
      // If we are running on a random flutter dev port on localhost, we point to the actual backend at 3000.
      final uri = Uri.base;
      if (uri.host == 'localhost' && uri.port != 3000) {
        _currentBaseUrl = 'http://localhost:3000';
      } else {
        _currentBaseUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
      }
    } else {
      // In mobile apps
      if (kReleaseMode) {
        _currentBaseUrl = _defaultProductionBaseUrl;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // 10.0.2.2 is the special IP to access host localhost from Android emulator
        _currentBaseUrl = _defaultAndroidEmulatorBaseUrl;
      } else {
        _currentBaseUrl = _defaultDevBaseUrl;
      }
    }
  }

  static String get baseUrl => _currentBaseUrl;

  static String normalizeUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (kIsWeb) return url;

    // In Android Emulator, localhost/127.0.0.1 must be mapped to 10.0.2.2
    if (defaultTargetPlatform == TargetPlatform.android && !kReleaseMode) {
      return url.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
    }
    return url;
  }

  static Future<void> setCustomBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      await prefs.remove('custom_api_base_url');
    } else {
      await prefs.setString('custom_api_base_url', url);
    }
    await initialize();
  }

  // Firebase configuration
  static const String firestoreDatabaseId = 'violeafydb';

  // PayU Environment Management ('Test' | 'Production')
  static Future<String> getPayUEnvironment() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('payu_environment');
    if (saved == 'Test' || saved == 'Production') {
      return saved!;
    }
    return kReleaseMode ? 'Production' : 'Test';
  }

  static Future<void> setPayUEnvironment(String environment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('payu_environment', environment);
  }
}
