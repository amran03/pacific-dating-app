import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_service.dart';
import 'notification_service.dart';
import 'presence_service.dart';
import 'supabase_service.dart';
import 'user_prefs.dart';

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

  @override
  void initState() {
    super.initState();
    // Jaribu baada ya frame ya kwanza — auth session huwa tayari hapo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncListeners());
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
        UserPrefs.instance.clear();
        PresenceService.stop();
        NotificationService.instance.stopListening();
        CallService.instance.stopListening();
      } else {
        _scheduleRetry();
      }
      return;
    }

    if (_activeUid == uid) return; // tayari active — usianzise upya.
    _activeUid = uid;
    _retryCount = 0;

    // Mapendeleo ya mtumiaji yanasomwa MARA MOJA.
    UserPrefs.instance.load(uid);
    PresenceService.start();
    // Real-time system notifications + incoming calls kwa user huyu.
    // Hizi zina retry yake ndani pia (uid tayari tunayo hapa).
    NotificationService.instance.startListening();
    CallService.instance.startListening();
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
