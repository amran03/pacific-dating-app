import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/presentation/call_screen.dart';
import 'notification_service.dart';
import 'push_sender.dart';

/// Real call signaling using Supabase Realtime Broadcast.
///
/// - Every signed-in user listens on their own private channel: `call:<uid>`.
///   The caller sends a `ring` event there — that's what brings up the
///   "Incoming call" screen for the peer, wherever they are in the app.
/// - As soon as the call starts, both sides connect to the shared channel
///   `call:<callId>` where WebRTC offer/answer/ICE candidates and events
///   (accept / decline / end) are exchanged (see CallScreen).
class CallService {
  CallService._internal();
  static final CallService instance = CallService._internal();

  /// GlobalKey of the app's navigator — used to push the Incoming call screen
  /// from anywhere (even while the user is on the dashboard).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  RealtimeChannel? _incomingChannel;
  String? _listeningUid;
  bool _ringing = false;

  bool get isListening => _incomingChannel != null;

  /// Wait for the channel to reach the SUBSCRIBED status before sending.
  /// Without this, broadcast messages sent right after `subscribe()`
  /// can get lost (the channel is not connected to the server yet) — the
  /// main reason WebRTC calls were unreachable / unanswered before.
  static Future<bool> ensureSubscribed(
    RealtimeChannel channel, {
    Duration timeout = const Duration(seconds: 6),
  }) {
    final completer = Completer<bool>();
    channel.subscribe((status, [Object? error]) {
      if (completer.isCompleted) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        completer.complete(true);
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        completer.complete(false);
      }
    });
    return completer.future.timeout(timeout, onTimeout: () => false);
  }

  /// Start listening for incoming calls (called once the user is logged in —
  /// see PresenceTracker).
  void startListening() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    // Already listening for this user — do not subscribe again (presence/auth
    // events fire often; reduces network chatter).
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

  /// Stop listening (logout / app closing).
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

  /// The caller uses this to ring the peer: it sends `ring` on the peer's
  /// private channel. Returns false if sending failed.
  Future<bool> sendRing({
    required String peerUid,
    required String callId,
    required CallType callType,
    required String callerName,
    String? callerAvatarUrl,
  }) async {
    final client = Supabase.instance.client;
    RealtimeChannel? channel;
    try {
      channel = client.channel('call:$peerUid');
      // We MUST see SUBSCRIBED before sending the ring — otherwise
      // the ring can get lost and the peer never receives the call.
      final subscribed = await ensureSubscribed(channel);
      if (!subscribed) {
        try {
          await client.removeChannel(channel);
        } catch (_) {}
        return false;
      }
      await channel.sendBroadcastMessage(event: 'ring', payload: {
        'callId': callId,
        'type': callType == CallType.video ? 'video' : 'audio',
        'callerName': callerName,
        'callerAvatar': callerAvatarUrl,
        'callerUid': client.auth.currentUser?.id,
      });
      // Wait briefly so the message reaches the server before closing the channel.
      await Future.delayed(const Duration(milliseconds: 300));
      await client.removeChannel(channel);
      return true;
    } catch (_) {
      try {
        if (channel != null) await client.removeChannel(channel);
      } catch (_) {}
      return false;
    }
  }

  /// Logs a "missed call" into the peer's notifications —
  /// called by CallScreen when the call was not answered (timeout) or
  /// was declined. The row is NOT deleted — it stays in the history and is
  /// marked read=true once the user sees it.
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
      // FCM — mpokeaji apate missed-call alert hata akiwa nje ya app.
      unawaited(PushSender.send(
        toUid: toUid,
        type: 'missed_call',
        title: declined ? 'Call declined 📵' : 'Missed call 📵',
        body: declined
            ? '$fromName did not answer ${isVideo ? 'video call' : 'your voice call'}.'
            : 'You missed ${isVideo ? 'video call' : 'voice call'} from $fromName.',
        fromUid: fromUid,
        fromName: fromName,
      ));
    } catch (_) {}
  }

  static String _sanitize(String s) => s.replaceAll('|', '/');

  void _onIncomingRing(dynamic payload) {
    if (payload is! Map) return;
    final callId = payload['callId']?.toString();
    if (callId == null || callId.isEmpty) return;

    // The user is on another call / a ring is already active — ignore.
    if (_ringing) return;
    _ringing = true;

    final context = navigatorKey.currentContext;
    final bool inForeground = context != null && context.mounted;

    // Always raise the full-screen ringing notification so the call rings
    // even when the user is in another app (Realtime callbacks do not fire
    // when the app is backgrounded — the FCM push path covers that case).
    final String callKind =
        payload['type'] == 'video' ? 'video' : 'audio';
    final String callerDisplayName =
        _sanitize(payload['callerName']?.toString() ?? 'Unknown');
    final String callerId = payload['callerUid']?.toString() ?? '';
    final callPayload =
        'call|$callId|$callKind|$callerDisplayName|$callerId';
    unawaited(NotificationService.instance.showIncomingCall(
      title: 'Incoming $callKind call',
      body: '$callerDisplayName is calling you…',
      payload: callPayload,
    ));

    if (!inForeground) return;
    CallScreen.push(
      context,
      callType: payload['type'] == 'video' ? CallType.video : CallType.audio,
      peerName: payload['callerName']?.toString() ?? 'Unknown',
      peerAvatarUrl: payload['callerAvatar']?.toString(),
      isOutgoing: false,
      peerUid: payload['callerUid']?.toString() ?? '',
      callId: callId,
    ).whenComplete(() => _ringing = false);
    // CallScreen iko wazi sasa:
    //  - futa arifa ya ring (ingefungama kwenye tray — ongoing + autoCancel
    //    false — na kusababisha "ring" iliyokaa baada ya simu kuisha);
    //  - ondoa stash ya pending call (kuzuia PresenceTracker consumer
    //    kufungua CallScreen ya KATI kwenye hii hiyo).
    unawaited(NotificationService.instance.cancelIncomingCall(callId));
    NotificationService.consumePendingIncomingCall();
  }
}
