import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';
import 'package:pacific_dating_app/features/chat/presentation/call_screen.dart';
import 'package:pacific_dating_app/features/chat/presentation/individual_chat_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_service.dart';
import 'notification_service.dart';
import 'presence_service.dart';
import 'push_service.dart';
import 'supabase_service.dart';
import 'user_prefs.dart';
import 'zego_call_service.dart';

/// Presence + listeners tracker (chini ya MaterialApp).
///
/// MUHIMU — kwa nini Stateful + post-frame + retries:
/// tatizo la zamani lilikuwa startListening() ya notifications/calls
/// iliitwa ndani ya StreamBuilder builder (uid ikiwa bado null) na
/// haikuwahi kuitwa tena — matokeo: "messages haziji kama notification".
/// Hapa tunahakikisha:
///  1. listeners zinaanzishwa MARA MOJA baada ya login imethibitika
///     (post-frame callback, si wakati wa build),
///  2. kama uid bado haipo, tunajaribu tena (retry loop),
///  3. logout inasimamisha kila kitu.
class PresenceTracker extends StatefulWidget {
  const PresenceTracker({super.key});

  @override
  State<PresenceTracker> createState() => _PresenceTrackerState();
}

class _PresenceTrackerState extends State<PresenceTracker> {
  String? _activeUid;
  int _retryCount = 0;
  Timer? _routeConsumer;

  @override
  void initState() {
    super.initState();
    // Jaribu baada ya frame ya kwanza — auth session huwa tayari hapo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncListeners());
  }

  @override
  void dispose() {
    _stopRouteConsumer();
    super.dispose();
  }

  /// Hii inaitwa kila auth state inabadilika (kupitia didChangeDependencies
  /// hapana — tunasikiliza moja kwa moja ili kuepuka rebuild loops).
  void _syncListeners() {
    if (!SupabaseService.instance.isInitialized) {
      _scheduleRetry();
      return;
    }
    String? uid;
    try {
      uid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      uid = null;
    }

    if (uid == null || uid.isEmpty) {
      // Labda session bado inapakiwa — jaribu tena (max mara ~20).
      if (_activeUid != null) {
        // Tulikuwa na user — sasa hamna: logout.
        _activeUid = null;
        _retryCount = 0;
        _stopRouteConsumer();
        UserPrefs.instance.clear();
        PresenceService.stop();
        NotificationService.instance.stopListening();
        CallService.instance.stopListening();
        // ZEGO: dhisha call invitation service kwenye logout.
        unawaited(ZegoCallService.instance.uninit());
      } else {
        _scheduleRetry();
      }
      return;
    }

    if (_activeUid == uid) return; // tayari active — usianzise upya.
    _activeUid = uid;
    _retryCount = 0;

    // User preferences are loaded once.
    UserPrefs.instance.load(uid);
    PresenceService.start();
    // Realtime system notifications + incoming calls for this user
    // (each has its own internal retry; uid is already known here).
    NotificationService.instance.startListening();
    CallService.instance.startListening();
    // FCM token registration for background/killed push delivery
    // (no-op when Firebase is not configured — see PushService).
    PushService.registerAfterLogin(uid);
    // ZEGO call invitations: anza mara tu login ya Supabase
    // imethibitika (userID = Supabase uid iliyosafishwa).
    unawaited(ZegoCallService.instance.init(uid));
    // Notification-tap navigation: anza kuchukua stash za arifa
    // (chat/call deep-link) mara mtumiaji ameingia.
    _startRouteConsumer();
  }

  // ============================================================
  // NOTIFICATION TAP → NAVIGATION (flutter_local_notifications).
  // ============================================================
  // NotificationService.hifadhi payload ("stash") wakati mtumiaji
  // anagusa arifa — wakati huo navigator haipo bado (cold-start) au
  // ukurasa mwingine uko juu. Hakuna consumer lilipofungua hii;
  // hapa tunachukua stash na kufungua IndividualChatScreen / CallScreen.
  //
  // Mzunguko huu unaanza baada ya login na kusimama kwenye logout.
  void _startRouteConsumer() {
    _routeConsumer ??= Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _consumePendingRoutes(),
    );
  }

  void _stopRouteConsumer() {
    _routeConsumer?.cancel();
    _routeConsumer = null;
  }

  void _consumePendingRoutes() {
    if (!mounted || _activeUid == null) return;
    final nav = CallService.instance.navigatorKey.currentState;
    if (nav == null) return;

    // 1) Chat arifa iliyoguswa → fungua conversation. Ikiwa chat hiyo
    //    tayari iko wazi (viewingChatPeerUid), bado tunachukua stash
    //    ili isifungue tena wakati mwingine.
    final chat = NotificationService.consumePendingChatLaunch();
    if (chat != null) {
      final alreadyViewing =
          NotificationService.viewingChatPeerUid == chat.uid;
      if (!alreadyViewing) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => IndividualChatScreen(
              chat: ChatModel(
                id: chat.uid,
                name: chat.name,
                avatarUrl: chat.avatarUrl,
                lastMessage: '',
                timeSent: '',
              ),
            ),
          ),
        );
      }
    }

    // 2) Simu iliyoiningia (tap ya Answer / body ya arifa) → CallScreen
    //    MARA MOJA. `CallScreen.isActive` huzuia CallScreen ya pili
    //    ikiwa moja tayari iko wazi (mf. ring ya realtime ilifungua
    //    moja kwa moja; au Answer iliguswa mara mbili haraka).
    final call = NotificationService.consumePendingIncomingCall();
    if (call != null && !CallScreen.isActive) {
      CallScreen.push(
        nav.context,
        callType: call.isVideo ? CallType.video : CallType.audio,
        peerName: call.name,
        peerUid: call.uid,
        callId: call.callId,
        isOutgoing: false,
      );
    }
  }

  void _scheduleRetry() {
    if (!mounted || _retryCount >= 20) return;
    _retryCount++;
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _activeUid == null) _syncListeners();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Don't touch Supabase.instance before it is initialized — otherwise the
    // app crashes on launch when credentials aren't configured yet. In that
    // case AuthGate shows the setup screen, so this tracker does nothing.
    if (!SupabaseService.instance.isInitialized) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          // Anzisha listeners nje ya build (post-frame) ili kuepuka
          // setState-during-build na kuitwa mara nyingi.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncListeners();
          });
          if (snapshot.data?.session == null && _activeUid != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _activeUid = null;
              _stopRouteConsumer();
              UserPrefs.instance.clear();
              PresenceService.stop();
              NotificationService.instance.stopListening();
              CallService.instance.stopListening();
            });
          }
        }
        return const SizedBox.shrink();
      },
    );
  }
}
