import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_service.dart';
import 'notification_service.dart';
import 'presence_service.dart';
import 'supabase_service.dart';
import 'user_prefs.dart';

/// Widget rahisi ya to kala kutokea presence ya mtumiaji zangu.
///
/// Hii inafuata [PresenceService.start] kila mtumiaji ameingia (authenticated)
/// na [PresenceService.stop] kila ilogout / app isogwa. Hii ndiyo overlay
/// ndogo (sizero) ili kuweka "online status" ZIPASAHIHI kwenye app nzima.
class PresenceTracker extends StatelessWidget {
  const PresenceTracker({super.key});

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
        if (snapshot.hasData && snapshot.data?.session != null) {
          // Mapendeleo ya mtumiaji (read receipts, typing, online status,
          // discoverable) yanasomwa MARA MOJA — yanatumika kwenye chat,
          // presence na Discover bila kuuliza DB kila mara.
          final String? uid =
              Supabase.instance.client.auth.currentUser?.id;
          if (uid != null) {
            UserPrefs.instance.load(uid);
          }
          PresenceService.start();
          // Real-time system notifications for the logged-in user.
          NotificationService.instance.startListening();
          // Real-time incoming calls (ring channel ya mtumiaji).
          CallService.instance.startListening();
        } else {
          UserPrefs.instance.clear();
          PresenceService.stop();
          NotificationService.instance.stopListening();
          CallService.instance.stopListening();
        }
        return const SizedBox.shrink();
      },
    );
  }
}
