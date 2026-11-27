import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/config/env_config.dart';
import 'features/cart_checkout/domain/payment_gateway_config.dart';
import 'firebase_options.dart';
import 'app/main_app.dart';
 
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Load environment configurations (URLs, API keys)
  await EnvConfig.initialize();

  try {
    // 1. Initialize Firebase Core using CLI-generated options
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Enable Firestore debug logging only in debug mode
    FirebaseFirestore.setLoggingEnabled(kDebugMode);

    // 2. Connect to the native Firestore database 'violeafydb'
    debugPrint('[Main] Connecting to native database: ${EnvConfig.firestoreDatabaseId}');
    final firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: EnvConfig.firestoreDatabaseId,
    );

    // 3. STRICT STARTUP RULE: Retrieve active payment gateway directly from Firestore server
    //    (Source.server, no persistent caching, retained in runtime memory only for this session).
    await PaymentGatewayManager.instance.initializeFromServer(firestore: firestore);

  } catch (e) {
    final errorStr = e.toString();
    if (errorStr.contains('duplicate-app')) {
      debugPrint('[Main] Firebase already initialized via native provider. Continuing...');
    } else {
      debugPrint('[Main] Database initialization warning: $e');
    }
  }

  // Debug: Listen to Auth State changes
  firebase_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      debugPrint('[Main] Auth State: User signed in (${user.phoneNumber})');
    } else {
      debugPrint('[Main] Auth State: User signed out');
    }
  });

  runApp(
    const ProviderScope(
      child: LeafyMainApp(),
    ),
  );
}
