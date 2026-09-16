import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Keep import so AppLanguage stays initialized; UI is English-only now.
import 'core/localization/app_language.dart';
import 'core/localization/app_theme.dart';
import 'core/services/auth_gate.dart';
import 'core/services/call_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/presence_tracker.dart';
import 'core/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lugha na THEME iliyohifadhiwa — zinaweka kabla app haijafunguka.
  await AppLanguage.instance.load();
  await AppTheme.instance.load();

  // Supabase Initialization
  try {
    await SupabaseService.instance.initialize();
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  // Real (system) notifications
  await NotificationService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Theme is a ChangeNotifier. Language is English-only (AppLanguage is
    // kept only for compatibility) — single listener so the navigation
    // stack is never reset.
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: AppTheme.instance,
          builder: (context, _) {
            return MaterialApp(
              title: 'Pacific Dating App',
              debugShowCheckedModeBanner: false,
              navigatorKey: CallService.instance.navigatorKey,

              // FONT: Poppins — modern, readable, used by ALL screens.
              // Used by ALL app screens by default.
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFFFF4B72),
                  brightness: AppTheme.instance.isDark
                      ? Brightness.dark
                      : Brightness.light,
                ),
                textTheme: GoogleFonts.poppinsTextTheme(),
              ),

              // Builder wrapper — navigation stack is not rebuilt when the
              // theme changes. This avoids pushing back to welcome screen.
              builder: (context, child) {
                return Stack(
                  children: [
                    const PresenceTracker(),
                    child!,
                  ],
                );
              },
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

