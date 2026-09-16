import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_prefs.dart';

/// Real notifications:
///  - Listens to the Supabase `notifications` table in real-time.
///  - Shows a system (local) notification for every new row.
///  - Respects the user's `notifications_enabled` preference.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _userEnabled = true; // switch ya mtumiaji (users.notifications_enabled)
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  final Set<String> _seenIds = {};

  /// Inaitwa na ProfileSettings switch ili mabadiliko ya haraka yaitekeleze
  /// bila ku-subscribe upya.
  void setUserEnabled(bool enabled) => _userEnabled = enabled;

  Future<void> _fetchUserPreference(String uid) async {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('notifications_enabled')
          .eq('uid', uid)
          .maybeSingle();
      _userEnabled = row?['notifications_enabled'] != false;
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(settings);

      // Ask for permission on Android 13+ and iOS.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  /// Starts listening for new notifications for the logged-in user.
  void startListening() {
    final client = Supabase.instance.client;
    final String? uid = client.auth.currentUser?.id;
    if (uid == null || !_initialized) return;

    // Prevent duplicate subscriptions.
    if (_subscription != null) return;
    _fetchUserPreference(uid);
    _subscription ??= client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('to_uid', uid)
        .order('created_at', ascending: false)
        .limit(30)
        .listen(_onNotifications, onError: (e) {
      debugPrint('Notifications stream error: $e');
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _seenIds.clear();
  }

  Future<void> _onNotifications(List<Map<String, dynamic>> rows) async {
    // User amezima arifa kwenye Profile Settings — usionyeshe chochote.
    if (!_userEnabled) return;
    for (final row in rows) {
      final String id = row['id']?.toString() ?? '';
      if (id.isEmpty || _seenIds.contains(id)) continue;
      _seenIds.add(id);

      // Skip anything already marked as read (e.g. history).
      if (row['read'] == true) continue;

      await showNotification(
        id: id.hashCode,
        title: row['title']?.toString() ?? 'Pacific',
        body: row['description']?.toString() ?? '',
      );
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'pacific_general',
        'General Notifications',
        channelDescription: 'Matches, messages, gifts and coins',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        // Mapendeleo ya mtumiaji (Profile > Notifications):
        playSound: UserPrefs.instance.soundEnabled,
        enableVibration: UserPrefs.instance.vibrationEnabled,
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(id, title, body, details);
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }
}
