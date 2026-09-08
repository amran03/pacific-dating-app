import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'presence_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

/// Widget rahisi ya kwa kala kutokea presence ya mtumiaji zangu.
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
          PresenceService.start();
          // Real-time system notifications for the logged-in user.
          NotificationService.instance.startListening();
        } else {
          PresenceService.stop();
          NotificationService.instance.stopListening();
        }
        return const SizedBox.shrink();
      },
    );
  }
}
