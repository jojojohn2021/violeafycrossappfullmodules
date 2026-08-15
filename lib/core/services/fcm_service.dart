import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FCMService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Initialize FCM handlers
  Future<void> initialize({
    required Function(RemoteMessage message) onForegroundMessage,
    required Function(RemoteMessage message) onMessageOpenedApp,
  }) async {
    try {
      // 1. Request notification permissions (vital for iOS/Android 13+)
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('FCM Notification permission status: ${settings.authorizationStatus}');

      // 2. Configure Foreground messages (when app is active/open)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message received: ${message.notification?.title}');
        onForegroundMessage(message);
      });

      // 3. Configure Click action handler (when app is opened via notification click)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM Message click action triggered app open: ${message.data}');
        onMessageOpenedApp(message);
      });

      // 4. Handle initial message (if app was terminated and opened via notification)
      RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM App opened from terminated state via message: ${initialMessage.data}');
        onMessageOpenedApp(initialMessage);
      }
    } catch (e) {
      debugPrint('FCM Service Initialization Error: $e');
    }
  }

  // Retrieve messaging token for server-side push notification targetting
  Future<String?> getDeviceToken() async {
    try {
      if (kIsWeb) {
        // VAPID key is required for Web notifications. If configured, we pass it.
        return await _fcm.getToken();
      } else {
        return await _fcm.getToken();
      }
    } catch (e) {
      debugPrint('FCM Error fetching device token: $e');
      return null;
    }
  }

  // Subscribe to topics
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      debugPrint('FCM Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('FCM Subscription to topic $topic failed: $e');
    }
  }

  // Unsubscribe from topics
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      debugPrint('FCM Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('FCM Unsubscription from topic $topic failed: $e');
    }
  }
}
