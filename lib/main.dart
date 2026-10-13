import 'package:flutter/material.dart';

// Keep import so AppLanguage stays initialized; UI is English-only now.
import 'core/localization/app_language.dart';
import 'core/localization/app_theme.dart';
import 'core/services/auth_gate.dart';
import 'core/services/call_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/presence_tracker.dart';
import 'core/services/push_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/zego_call_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Stored language/theme — loaded before the app opens.
  await AppLanguage.instance.load();
  await AppTheme.instance.load();

  // Supabase Initialization
  try {
    await SupabaseService.instance.initialize();
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  // Push (FCM) — registers the background handler BEFORE runApp so
  // notifications arrive even when the app is backgrounded or killed.
  // Safe no-op when Firebase is not configured yet.
  await PushService.init();

  // Real (system) notifications
  await NotificationService.instance.initialize();

  // ZEGO call invitation: funga global navigatorKey (ile ile ya
  // MaterialApp hapo chini) kabla ya app kuanza — incoming-call UI
  // inapushwa kupitia hiyo key. init() wenyewe inaitwa baada ya login
  // (presence_tracker).
  ZegoCallService.instance.registerNavigatorKey();

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
              // Global navigatorKey — pia inatumika na ZEGO
              // (ZegoUIKitPrebuiltCallInvitationService) kwa
              // incoming-call UI; ni key moja tu (CallService).
              navigatorKey: CallService.instance.navigatorKey,

              // FONT: Poppins — modern, readable, used by ALL screens.
              // The full rounded design system (cards, dialogs, sheets,
              // inputs, buttons, chips) is defined once in AppTheme.theme().
              theme: AppTheme.instance.theme(),

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

