import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Hii inaondoa error ya FirebaseFirestore na DocumentSnapshot

// Weka import sahihi ya WelcomeScreen kulingana na ulivyoiweka kwenye folder structure yako:
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/welcome_screen.dart';
import 'package:pacific_dating_app/features/dashboard/presentation/screens/main_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
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

        if (snapshot.hasData && snapshot.data != null) {
          final String uid = snapshot.data!.uid;

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
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

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                if (userData != null && userData['isProfileComplete'] == true) {
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
  }
}