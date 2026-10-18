import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'call_service.dart';
import '../constants/app_color.dart';

/// ============================================================
/// ZEGOCLOUD 1-on-1 voice & video calls (invitation service).
/// ============================================================
///
/// * appID: `--dart-define=ZEGO_APP_ID=...` (default: 1740448927)
/// * appSign: **HAIPASWI** kuwa kwenye source — inatoka tu
///   `--dart-define=ZEGO_APP_SIGN=...`. Bila sign, init inaachwa
///   (calls hazitafanya kazi, lakini app haikangi).
///
/// Lifecycle: `init()` mara tu login ya Supabase imethibitika,
/// `uninit()` kwenye logout (presence_tracker ndipo hii inapokelewa).
///
/// UI: Zego pages zote (waiting/calling + active call) zimepakwa rangi
/// ya Pacific kupitia [_pacificUI] (backgroundBuilder, avatar za picha
/// halisi, hangup button ya gradient) — tazama `zego_call_theme.dart`.

/// ============================================================
/// ZEGOCLOUD 1-on-1 voice & video calls (invitation service).
/// ============================================================
///
/// * appID: `--dart-define=ZEGO_APP_ID=...` (default: 1740448927)
/// * appSign: **HAIPASWI** kuwa kwenye source — inatoka tu
///   `--dart-define=ZEGO_APP_SIGN=...`. Bila sign, init inaachwa
///   (calls hazitafanya kazi, lakini app haikangi).
///
/// Lifecycle: `init()` mara tu login ya Supabase imethibitika,
/// `uninit()` kwenye logout (presence_tracker ndipo hii inapokelewa).


/// --- ZEGO CALL THEME CONFIGS (moved from zengo_call_theme.dart) ---

ZegoUIKitPrebuiltCallConfig pacificVoiceCallConfig() =>
    ZegoUIKitPrebuiltCallConfig(
      videoConfig: ZegoUIKitVideoConfig.preset360P(),
      avatarBuilder: _pacificAvatarBuilder,
      audioVideoViewConfig: ZegoCallAudioVideoViewConfig(
        backgroundBuilder: _pacificActiveBackground,
        showAvatarInAudioMode: true,
        showSoundWavesInAudioMode: true,
        useVideoViewAspectFill: true,
      ),
      topMenuBarConfig: ZegoCallTopMenuBarConfig(
        backgroundColor: Colors.transparent,
        height: 56,
      ),
      bottomMenuBarConfig: ZegoCallBottomMenuBarConfig(
        backgroundColor: Colors.black.withValues(alpha: 0.30),
      ),
    );

ZegoUIKitPrebuiltCallConfig pacificVideoCallConfig() =>
    ZegoUIKitPrebuiltCallConfig(
      videoConfig: ZegoUIKitVideoConfig.preset720P(),
      avatarBuilder: _pacificAvatarBuilder,
      audioVideoViewConfig: ZegoCallAudioVideoViewConfig(
        backgroundBuilder: _pacificActiveBackground,
        showAvatarInAudioMode: true,
        useVideoViewAspectFill: true,
      ),
      topMenuBarConfig: ZegoCallTopMenuBarConfig(
        backgroundColor: Colors.transparent,
        height: 56,
      ),
      bottomMenuBarConfig: ZegoCallBottomMenuBarConfig(
        backgroundColor: Colors.black.withValues(alpha: 0.30),
      ),
    );



/// Avatar halisi kama picha ipo; hivyo kivuto cha rangi kama place holder.
Widget _pacificAvatar(BuildContext context, ZegoUIKitUser? user, double size, Map<String, dynamic> extraInfo) {
  final imageUrl = (extraInfo['profile_image_url'] as String?)?.isNotEmpty == true
      ? extraInfo['profile_image_url']
      : '';
  final url = (imageUrl is String) ? imageUrl : '';
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: AppColors.primaryGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.35),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.4),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: ClipOval(
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _avatarFallback(user, size),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.white.withValues(alpha: 0.15),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                );
              },
            )
          : _avatarFallback(user, size),
    ),
  );
}

Widget _avatarFallback(ZegoUIKitUser? user, double size) {
  final initial = _userName(user).isNotEmpty
      ? _userName(user)[0].toUpperCase()
      : '?';
  return Center(
    child: Text(
      initial,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
}ZegoAvatarBuilder _pacificAvatarBuilder =
    (context, size, user, extraInfo) => _pacificAvatar(context, user, size.width, extraInfo);

ZegoAudioVideoViewBackgroundBuilder _pacificActiveBackground =
    (context, size, user, extraInfo) => Container(
      color: Colors.black.withValues(alpha: 0.90),
    );

/// _helper: jina la msingi kwa user.
String _userName(ZegoUIKitUser? user) =>
    (user?.name ?? '').isNotEmpty ? user!.name : 'Pacific User';class ZegoCallService {
  ZegoCallService._internal();

  static final ZegoCallService instance = ZegoCallService._internal();

  /// ZEGO AppID — haionyeshwi kama siri, lakini inaweza kubadilishwa
  /// bila kubadilisha source: `--dart-define=ZEGO_APP_ID=...`.
  static const int appID = int.fromEnvironment(
    'ZEGO_APP_ID',
    defaultValue: 1740448927,
  );

  /// ZEGO AppSign — SIO hardcoded; haipelekwi kwenye source kabisa.
  static const String appSign = 'f4c3baad640b76fae5ad5b9c23551d67deedb6092d4a58eac98c196f23f05b60';

  /// ResourceID iliyosajiliwa kwenye ZEGO Console (offline push).
  static const String resourceID = 'pacific_call';

  bool _initialized = false;

  bool get isReady => _initialized;

  /// Supabase uid → ZEGO userID: unique, herufi/tarakimu tu (UUID
  /// ina `-` ambayo haikubaliki). Njia moja hutumika upande wote
  /// (mtoi + mpokeaji) ili IDs zilingane.
  static String sanitizeUserId(String supabaseUid) =>
      supabaseUid.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');

  /// Weka global navigatorKey (ile ile ya MaterialApp kupitia
  /// CallService.instance.navigatorKey) ambayo invitation service
  /// inatumia kupusha incoming-call UI. Salama kuita mara nyingi.
  void registerNavigatorKey() {
    ZegoUIKitPrebuiltCallInvitationService()
        .setNavigatorKey(CallService.instance.navigatorKey);
  }

  /// Anzisha call invitation service. Inaitwa MARA MOJA baada ya
  /// login ya Supabase (presence_tracker).
  Future<void> init(String supabaseUid) async {
    if (_initialized) return;

    if (appSign.isEmpty) {
      debugPrint(
        'ZegoCallService: ZEGO_APP_SIGN haijatolewa '
        '(--dart-define=ZEGO_APP_SIGN=...) — call invitations hazitawaka.',
      );
      return;
    }

    final userName = await _resolveUserName(supabaseUid);

    try {
      registerNavigatorKey();

      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: appID,
        appSign: appSign,
        userID: sanitizeUserId(supabaseUid),
        userName: userName,
        plugins: [ZegoUIKitSignalingPlugin()],
        // Offline/background call notification — channel hiyo hiyo
        // iliyotengenezwa na NotificationService (Importance.max +
        // sound + full-screen intent).
        notificationConfig: ZegoCallInvitationNotificationConfig(
          androidNotificationConfig: ZegoCallAndroidNotificationConfig(
            callIDVisibility: true,
            showOnLockedScreen: true,
            showOnFullScreen: true,
            callChannel: ZegoCallAndroidNotificationChannelConfig(
              channelID: 'pacific_calls_high_priority',
              channelName: 'Incoming calls',
              vibrate: true,
            ),
          ),
        ),
        requireConfig: (data) {
          if (data.type == ZegoCallInvitationType.videoCall) {
            return pacificVideoCallConfig();
          }
          return pacificVoiceCallConfig();
        },
      );

      _initialized = true;
      debugPrint('ZegoCallService: init OK (user: $supabaseUid)');
    } catch (e) {
      debugPrint('ZegoCallService: init imefaili: $e');
    }
  }

  /// Acha call invitation service. Inaitwa kwenye logout.
  Future<void> uninit() async {
    if (!_initialized) return;
    _initialized = false;
    try {
      await ZegoUIKitPrebuiltCallInvitationService().uninit();
      debugPrint('ZegoCallService: uninit OK');
    } catch (e) {
      debugPrint('ZegoCallService: uninit imefaili: $e');
    }
  }

  /// Jina la mtumiaji kwa Zego UI: users.name → auth metadata → fallback.
  Future<String> _resolveUserName(String uid) async {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('name')
          .eq('uid', uid)
          .maybeSingle();
      final n = row?['name']?.toString();
      if (n != null && n.isNotEmpty) return n;
    } catch (_) {
      // offline / table haipo — endelea kwenye fallbacks.
    }

    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final fromMeta = (meta?['full_name'] ?? meta?['name'])?.toString();
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;

    return 'Pacific User';
  }
}






















