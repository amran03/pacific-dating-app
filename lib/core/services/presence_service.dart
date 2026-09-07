import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// REAL-TIME PRESENCE (Online Status) za Pacific Dating App.
///
///  - Inahifadhi `isOnline` + `lastSeen` kwenye users/{uid} doc.
///  - Heartbeat inafanya `goOnline()` kila ~45s ili app iwe yafungwe.
///  - `stop()` inaweka `isOnline=false` + lastSeen wakati ukiwaza.
///
/// Tofauti ya muundo wa WHATSAPP:
///  - "Online" inaonekana ikiwa `isOnline == true` NA lastSeen imekaho
///    nsiendo ya 90s. Kama mtumiaji hayupo na muda nyinginya kwa zaidi
///    kuwa 90s, online inawimbuka na muonekano za `lastSeen`.
///  - Kwa sababu Firestore hadziweze ku-runa code ciotomatiki kwa muda,
///    tunatokea na lastSeen timestamp ilivo onesha online kamwe kama
///    huduma ya nje (mfano Firebase Auth presence) iwasha.
class PresenceService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? _myUid;
  static Timer? _heartbeatTimer;

  /// Wakati wa muda (seconds) ili mtumiaji wasiwe onisa online.
  static const int onlineTimeoutSeconds = 90;

  static String? get myUid => _myUid;

  /// Ili app iwe yafungwa na mtumiaji ameingia — inaftuka heartbeat.
  static void start() {
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    if (_myUid == null) return;

    _goOnline();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _goOnline();
    });
  }

  /// Ili app inasogwa / ilogout — inaweka isOnline=false.
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
    await _setPresence(_myUid!, online: true);
  }

  static Future<void> _setPresence(String uid, {required bool online}) async {
    await _db
        .collection('users')
        .doc(uid)
        .set(
      {
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    )
        .catchError((_) {});
  }

  /// Stream ya presence ya peer — inayotokea na data za users/{uid} doc.
  static Stream<Map<String, dynamic>?> streamPeerPresence(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) => snap.data());
  }

  /// Muonekano sahihi: inaonekana "online" ikiwa isOnline true NA lastSeen
  /// imekaho nsiendo ya [onlineTimeoutSeconds].
  static bool isOnline(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['isOnline'] != true) return false;
    final ts = data['lastSeen'];
    if (ts is! Timestamp) return false;
    return DateTime.now().difference(ts.toDate()).inSeconds <
        onlineTimeoutSeconds;
  }

  /// Maandishi ya lastSeen ("2h ago", "3d ago") — huwekwe na SW ikiwa
  /// tafsiri ya lugha ipo.
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