import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/presentation/call_screen.dart';

/// Real call signaling to kutumia Supabase Realtime Broadcast.
///
/// - Kila user aliyeingia anasikiliza channel yake ya faragha: `call:<uid>`.
///   Caller anatuma event ya `ring` huko — ndiyo inayomleta screen ya
///   "Incoming call" to mwenzake hata awe popote app-ni.
/// - Mara call inapoanza, pande zote mbili zinaunganisha channel ya pamoja
///   `call:<callId>` ambapo WebRTC offer/answer/ICE candidates na events
///   (accept / decline / end) zinabadilishana (ona CallScreen).
class CallService {
  CallService._internal();
  static final CallService instance = CallService._internal();

  /// GlobalKey ya navigator ya app — inatumiwa ku-push Incoming call screen
  /// kutoka popote (hata user akiwa kwenye dashboard).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  RealtimeChannel? _incomingChannel;
  String? _listeningUid;
  bool _ringing = false;

  bool get isListening => _incomingChannel != null;

  /// Anza kusikiliza simu zinazoingia (waitwa mara moja user akiwa logged-in —
  ///ona PresenceTracker).
  void startListening() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    // TAYARI tunasikiliza to user huyu — usijiunge upya (presence/auth
    // events hufya mara nyingi; tunapunga network chatter).
    if (_incomingChannel != null && _listeningUid == uid) return;

    stopListening();
    _listeningUid = uid;

    _incomingChannel = client
        .channel('call:$uid')
        .onBroadcast(event: 'ring', callback: (payload) {
          _onIncomingRing(payload);
        })
        .subscribe();
  }

  /// Simama kusikiliza (logout / app closing).
  Future<void> stopListening() async {
    final channel = _incomingChannel;
    _incomingChannel = null;
    _listeningUid = null;
    if (channel != null) {
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Caller anatumia hii kumwita mwenzake: inatuma `ring` kwenye channel ya
  /// faragha ya mwenzake. Inarudisha false kama kutuma kumeshindikana.
  Future<bool> sendRing({
    required String peerUid,
    required String callId,
    required CallType callType,
    required String callerName,
    String? callerAvatarUrl,
  }) async {
    final client = Supabase.instance.client;
    try {
      final channel = client.channel('call:$peerUid');
      channel.subscribe();
      await channel.sendBroadcastMessage(event: 'ring', payload: {
        'callId': callId,
        'type': callType == CallType.video ? 'video' : 'audio',
        'callerName': callerName,
        'callerAvatar': callerAvatarUrl,
        'callerUid': client.auth.currentUser?.id,
      });
      await client.removeChannel(channel);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Huandikisha "missed call" kwenye notifications za mwenzake —
  /// inaitwa na CallScreen pale simu haikujibiwa (timeout) au ilikataliwa.
  /// Row hii HAIFUTWI — inabaki kwenye history na inaashiria read=true
  /// mtumiaji akishaiona.
  static Future<void> logMissedCall({
    required String toUid,
    required String fromUid,
    required String fromName,
    required bool isVideo,
    bool declined = false,
  }) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'to_uid': toUid,
        'from_uid': fromUid,
        'from_name': fromName,
        'type': 'missed_call',
        'title': declined ? 'Call declined 📵' : 'Missed call 📵',
        'description': declined
            ? '$fromName did not answer ${isVideo ? 'video call' : 'your voice call'}.'
            : 'You missed ${isVideo ? 'video call' : 'voice call'} from $fromName.',
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  void _onIncomingRing(dynamic payload) {
    if (payload is! Map) return;
    final callId = payload['callId']?.toString();
    if (callId == null || callId.isEmpty) return;

    // User yuko kwenye call nyingine / ring inaendelea — ignore.
    if (_ringing) return;
    _ringing = true;

    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      _ringing = false;
      return;
    }

    CallScreen.push(
      context,
      callType: payload['type'] == 'video' ? CallType.video : CallType.audio,
      peerName: payload['callerName']?.toString() ?? 'Unknown',
      peerAvatarUrl: payload['callerAvatar']?.toString(),
      isOutgoing: false,
      peerUid: payload['callerUid']?.toString() ?? '',
      callId: callId,
    ).whenComplete(() => _ringing = false);
  }
}
