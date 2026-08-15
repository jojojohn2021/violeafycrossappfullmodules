import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/config/env_config.dart';
import 'firebase_options.dart';
import 'app/main_app.dart';
 
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment configurations (URLs, API keys)
  await EnvConfig.initialize();

  // Proactive Network Health Check (Skipped on Web to avoid dart:io crashes)
  if (!kIsWeb) {
    try {
      debugPrint('[Main] Probing network connectivity...');
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        debugPrint('[Main] Internet reachability confirmed.');
      }
    } catch (_) {
      debugPrint('[Main] Warning: No internet reachability detected. Emulator network might be disconnected.');
    }
  }

  try {
    // 1. Initialize Firebase Core using CLI-generated options
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Enable Firestore debug logging to catch connection issues
    FirebaseFirestore.setLoggingEnabled(true);

    // 2. Explicitly verify connection to the native Firestore database 'violeafydb'
    debugPrint('[Main] Connecting to native database: ${EnvConfig.firestoreDatabaseId}');
    final firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: EnvConfig.firestoreDatabaseId,
    );

    // Proactive connectivity check (light document probe)
    try {
      await firestore.collection('products').limit(1).get().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Firestore probe timed out. Verify "${EnvConfig.firestoreDatabaseId}" exists.'),
      );
      debugPrint('[Main] Native Database SDK verified successfully.');
    } on FirebaseException catch (fe) {
      if (fe.code == 'permission-denied') {
        debugPrint('[Main] Firebase Core & Firestore SDK initialized successfully (Database probe restricted by security rules: [cloud_firestore/permission-denied]).');
      } else {
        debugPrint('[Main] Firebase probe warning [${fe.code}]: ${fe.message}');
      }
    } catch (e) {
      debugPrint('[Main] Database probe info: $e');
    }

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
