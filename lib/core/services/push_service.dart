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
      // Mtumiaji aligusa arifa ya FCM iliyonyeshwa na mfumo (app ilikuwa
      // background, process bado iko hai) — bila listener hii hakuna
      // routing: app ingefunguka tu bila kufungua chat/call husika.
      // (getInitialMessage hapo chini inashughulikia cold-start tu.)
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedMessage);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _routeMessage(initial.data);
    } catch (_) {}
  }

  /// App ilifunguliwa kwa kugusa arifa ya FCM iliyonyeshwa na mfumo wa
  /// iOS/Android (notification payload — k.m. ya simu). Routing ni kama
  /// mtapato wa arifa: fungua chat, au weka call pending kwa UI.
  static void _onOpenedMessage(RemoteMessage msg) {
    final data = msg.data;
    final type = data['type']?.toString() ?? '';
    NotificationService.instance.handlePushTap(
      type == 'call' ? encodeCallPayload(data) : encodeChatPayload(data),
    );
  }

  /// Call after login. Fetches the FCM token, requests Android 13+
  /// permission, and stores the token on the user row.
  ///
  /// Muhimu: inatumia RPC `register_fcm_token` KWANZA (SECURITY DEFINER)
  /// kwa sababu hakuna RLS UPDATE policy kwenye `users` — direct update
  /// ingeshindwa kimya (rows 0). RPC ikiwa haipo bado (migration
  /// haija-run), inajaribu direct update kama fallback.
  static Future<void> registerAfterLogin(String uid) async {
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        try {
          final currentUid =
              Supabase.instance.client.auth.currentUser?.id;
          if (currentUid == null) return;
          await _saveToken(t);
        } catch (_) {}
      });
    } catch (_) {}
  }

  /// Hifadhi FCM token — RPC kwanza (inapita RLS salama), fallback
  /// direct update (kwa DB yenye policy ya zamani).
  static Future<void> _saveToken(String token) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    bool saved = false;
    try {
      await client.rpc('register_fcm_token', params: {'p_token': token});
      saved = true;
    } catch (e) {
      debugPrint('Pacific: register_fcm_token RPC missing ($e) — fallback');
    }
    if (!saved) {
      try {
        final res = await client
            .from('users')
            .update({'fcm_token': token})
            .eq('uid', uid)
            .select('fcm_token');
        saved = (res as List).isNotEmpty;
      } catch (_) {}
    }
    if (!saved) {
      debugPrint(
          'Pacific: FCM token NOT saved — run 20261018130000 migration. '
          'Push nje ya app haitafanya kazi mpaka hapo.');
    }
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
