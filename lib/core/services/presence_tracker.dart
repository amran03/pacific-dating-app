import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'presence_service.dart';

/// Widget rahisi ya kwa kala kutokea presence ya mtumiaji zangu.
///
/// Hii inafuata [PresenceService.start] kila mtumiaji ameingia (authenticated)
/// na [PresenceService.stop] kila ilogout / app isogwa. Hii ndiyo overlay
/// ndogo (sizero) ili kuweka "online status" ZIPASAHIHI kwenye app nzima.
class PresenceTracker extends StatelessWidget {
  const PresenceTracker({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.session != null) {
          PresenceService.start();
        } else {
          PresenceService.stop();
        }
        return const SizedBox.shrink();
      },
    );
  }
}
