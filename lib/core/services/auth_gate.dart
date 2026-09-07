import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pacific_dating_app/core/localization/app_language.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/welcome_screen.dart';
import 'package:pacific_dating_app/features/dashboard/presentation/screens/main_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF4B72),
                  ),
                ),
              );
            }

            final session = snapshot.data?.session;

            if (session != null) {
              final String uid = session.user.id;

              return FutureBuilder<PostgrestMap?>(
                future: Supabase.instance.client
                    .from('users')
                    .select()
                    .eq('uid', uid)
                    .maybeSingle(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF4B72),
                        ),
                      ),
                    );
                  }

                  if (userSnapshot.hasData && userSnapshot.data != null) {
                    final userData = userSnapshot.data!;
                    if (userData['is_profile_complete'] == true) {
                      return const MainDashboardScreen();
                    }
                  }

                  return const WelcomeScreen();
                },
              );
            }

            return const WelcomeScreen();
          },
        );
      },
    );
  }
}
