import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_prefs.dart';

class PresenceService {
  // Lazy on purpose: a static field initializer would call
  // Supabase.instance during class-load, before Supabase.initialize() runs,
  // and crash with "You must initialize the supabase instance".
  static SupabaseClient get _client => Supabase.instance.client;

  static String? _myUid;
  static Timer? _heartbeatTimer;
  static const int onlineTimeoutSeconds = 90;

  static String? get myUid => _myUid;

  static void start() {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    // TAYARI tunafuatilia user huyu — usianzise upya timer wala
    // kutuma DB update (hii inapunguza network chatter kutokana na
    // onAuthStateChange kufya kila token refresh / rebuild).
    if (_heartbeatTimer != null && _myUid == uid) return;

    _myUid = uid;
    _goOnline();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _goOnline();
    });
  }

  static Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_myUid == null) return;
    final uid = _myUid!;
    _myUid = null;
    await _setPresence(uid, online: false);
  }

  static Future<void> _goOnline() async {
    if (_myUid == null) return;
    // User amezima "Show Online Status" — tunaacha is_online=false
    // ili wengine wasimuone kama yuko online (privacy yake inaheshimiwa).
    if (!UserPrefs.instance.showOnlineStatusEnabled) {
      await _setPresence(_myUid!, online: false);
      return;
    }
    await _setPresence(_myUid!, online: true);
  }

  static Future<void> _setPresence(String uid, {required bool online}) async {
    try {
      await _client.from('users').update({
        'is_online': online,
        'last_seen': DateTime.now().toIso8601String(),
      }).eq('uid', uid);
    } catch (_) {}
  }

  static Stream<Map<String, dynamic>?> streamPeerPresence(String uid) {
    return _client
        .from('users')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .map((event) => event.isNotEmpty ? event.first : null);
  }

  static bool isOnline(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['is_online'] != true) return false;
    final lastSeenStr = data['last_seen'];
    if (lastSeenStr == null) return false;
    final lastSeen = DateTime.tryParse(lastSeenStr);
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen).inSeconds < onlineTimeoutSeconds;
  }

  static String lastSeenLabel(DateTime? lastSeen, {String? swPrefix}) {
    if (lastSeen == null) return 'offline';
    final diff = DateTime.now().difference(lastSeen);
    final suffix = swPrefix ?? 'ago';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s $suffix';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m $suffix';
    if (diff.inHours < 24) return '${diff.inHours}h $suffix';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d $suffix';
  }
}
