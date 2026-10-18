import 'package:flutter/material.dart';

// Keep import so AppLanguage stays initialized; UI is English-only now.
import 'package:pacific_dating_app/core/localization/app_language.dart';
import 'package:pacific_dating_app/core/localization/app_theme.dart';
import 'package:pacific_dating_app/core/services/auth_gate.dart';
import 'package:pacific_dating_app/core/services/call_service.dart';
import 'package:pacific_dating_app/services/connectivity_service.dart';
import 'package:pacific_dating_app/core/services/notification_service.dart';
import 'package:pacific_dating_app/core/services/presence_tracker.dart';
import 'package:pacific_dating_app/core/services/push_service.dart';
import 'package:pacific_dating_app/core/services/supabase_service.dart';
import 'package:pacific_dating_app/core/services/unread_messages_service.dart';
import 'package:pacific_dating_app/core/services/zego_call_service.dart';
import 'package:pacific_dating_app/core/widgets/offline_toast.dart';

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

  // Mtandao (offline detection) — toast fupi "Hakuna internet" (chini ya
  // sekunde 5, inaondoka yenyewe) inasikiliza kutoka MaterialApp.builder
  // hapo chini (OfflineToastListener).
  ConnectivityService.instance.start();

  // Hesabu za ujumbe usiosomwa (badge) — subscription MOJA iliyoshirikishwa
  // na chat list + icon ya Chat; pia inafuta count papo hapo chat
  // inapofunguliwa (UnreadMessagesService.openChat).
  UnreadMessagesService.instance.start();

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
                    // Toast ya offline (chini ya sekunde 5, si banner ya
                    // kudumu) — inasikiliza tu; hakuna UI ya kudumu.
                    const OfflineToastListener(),
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

