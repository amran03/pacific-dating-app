import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';
import 'push_bg_handler.dart' show firebaseBgHandler;

// ============================================================
// PUSH SERVICE — FCM wiring for background/killed notifications.
// ============================================================
//
// Supabase Realtime only runs while the app process is alive. To reach
// a backgrounded/killed app we use Firebase Cloud Messaging data
// messages, fanned out by the `send-push` Supabase Edge Function.
//
// SAFE WITHOUT FIREBASE: if google-services.json is missing or Firebase
// init fails, every method below degrades to a no-op and the app keeps
// working with foreground realtime notifications only.
class PushService {
  PushService._();
  static bool _ready = false;

  /// Call BEFORE runApp (after WidgetsFlutterBinding.ensureInitialized).
  /// Registers the background handler; never throws.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);
      _ready = true;
    } catch (e) {
      debugPrint('Pacific: Firebase not configured ($e) — push disabled.');
      _ready = false;
    }
    if (!_ready) return;
    try {
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _routeMessage(initial.data);
    } catch (_) {}
  }

  /// Call after login. Fetches the FCM token, requests Android 13+
  /// permission, and stores the token on the user row.
  static Future<void> registerAfterLogin(String uid) async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await Supabase.instance.client.from('users').update(
        {'fcm_token': token},
      ).eq('uid', uid);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        try {
          final currentUid =
              Supabase.instance.client.auth.currentUser?.id;
          if (currentUid == null) return;
          await Supabase.instance.client.from('users').update(
            {'fcm_token': t},
          ).eq('uid', currentUid);
        } catch (_) {}
      });
    } catch (_) {}
  }

  static Future<void> _onForegroundMessage(RemoteMessage msg) async {
    _routeMessage(msg.data, showBanner: true);
  }

  /// Shared router for foreground FCM + notification-tap payloads.
  static void _routeMessage(
    Map<String, dynamic> data, {
    bool showBanner = false,
  }) {
    final type = data['type']?.toString() ?? '';
    if (type == 'call') {
      NotificationService.instance.showIncomingCall(
        title: data['title']?.toString() ?? 'Incoming call',
        body: data['body']?.toString() ?? '',
        payload: encodeCallPayload(data),
      );
      return;
    }
    final payload = encodeChatPayload(data);
    if (showBanner) {
      NotificationService.instance.showFromPush(
        title: data['title']?.toString() ?? 'Pacific',
        body: data['body']?.toString() ?? '',
        payload: payload,
      );
    } else {
      NotificationService.instance.handlePushTap(payload);
    }
  }

  static String encodeChatPayload(Map<String, dynamic> d) {
    final fromUid = d['from_uid']?.toString() ?? '';
    final fromName = d['from_name']?.toString() ?? 'User';
    final type = d['type']?.toString() ?? 'message';
    return '$type|$fromUid|$fromName';
  }

  static String encodeCallPayload(Map<String, dynamic> d) {
    final callId = d['call_id']?.toString() ?? '';
    final isVideo = d['is_video']?.toString() == 'true';
    final callerUid = d['from_uid']?.toString() ?? '';
    final callerName = d['from_name']?.toString() ?? 'Unknown';
    return 'call|$callId|${isVideo ? 'video' : 'audio'}|$callerName|$callerUid';
  }
}
