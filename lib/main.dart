import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Hakikisha njia hii ya import inaendana na ulipoweka faili lako la WelcomeScreen
import 'core/localization/app_language.dart';
import 'core/localization/app_theme.dart';
import 'core/services/auth_gate.dart';
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

  @override
  Widget build(BuildContext context) {
    // FIX: Lugha (EN/SW) na THEME (Light/Dark) ni ChangeNotifiers.
    // Tuna nested ListenableBuilders ili zis RESET navigation stack.
    // Kila mabadiliko, tunarebuild wrapper (theme/locale), lakini
    // Navigator yenyewe inabaki salama kwenye child yake.
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: AppTheme.instance,
          builder: (context, _) {
            return MaterialApp(
              title: 'Pacific Dating App',
              debugShowCheckedModeBanner: false,

              // FONT: Poppins — font nzuri, ya kisasa na inasomeka vizuri.
              // Inatumiwa na screens ZOTE za app kwa default.
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

              // FIX: Builder wrapper — navigation stack hairebuild-i
              // wakati theme/language inabadilika. Hii inaepusha bug ya
              // kurudishwa welcome screen kila mtumiaji anapobadilisha lugha.
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

