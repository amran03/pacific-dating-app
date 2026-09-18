import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_service.dart';
import 'user_prefs.dart';

// ============================================================
// NOTIFICATION SERVICE — arifa za ujumbe kama WhatsApp
// ============================================================
//
// MTIRIRIKO (flow) wa arifa ya ujumbe:
//   A anamtumia B ujumbe (individual_chat_screen._sendMessage)
//     -> INSERT messages (chat kati ya A na B)
//     -> INSERT notifications (to_uid = B, from_uid = A)
//   B (NotificationService hapa):
//     -> stream ya notifications inaona row mpya (realtime)
//     -> inaonyesha SYSTEM notification (tray) yenye jina la A
//     -> B akigusa arifa -> IndividualChatScreen ya A inafunguka
//
// BADGES / COUNT (icon ya Chat + chat list):
//   Count inahesabiwa kutoka messages (receiver_id = mimi, seen = false).
//   Ukifungua chat, _markMessagesAsSeen inaweka seen = true -> count
//   inatoweka kiotomatiki. Arifa za tray zinafutwa na clearMessageNotificationsFor.
//
// MUHIMU — kwa nini stream HAINA .eq() filters:
//   `.stream().eq('to_uid', uid)` kwenye supabase-dart inaongeza filter
//   kama query param ya realtime. Kwa DB/columns za zamani au realtime
//   iliyosanidiwa tofauti, filter hii inaweza kurudisha rows 0 milele
//   (ndiyo chanzo cha awali cha "messages haziji kama notification").
//   Badala yake tunasikiliza rows 50 za mwisho kisha tunachuja
//   client-side: to_uid == mimi && read == false && fresh. Hii daima
//   inafanya kazi bila kujali realtime config ya server.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firstSnapshotReceived = false; // snapshot ya kwanza = historia
  bool _userEnabled = true; // switch ya mtumiaji (users.notifications_enabled)
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  final Set<String> _seenIds = {};
  String? _pendingLaunchPayload;

  /// Pending chat launch from notification tap (kwa app killed case;
  /// consumer generic - mwisho wa tree unaweza kuitafuta na kuitimize).
  static String? _pendingChatUid;
  static String? _pendingChatName;
  static String? _pendingChatAvatarUrl;

  /// Peer uid wa chat iliyo wazi kwa sasa — arifa za 'message' kutoka
  /// huyu hazionyeshwi (user yuko kwenye chat, ataona ujumbe papo hapo;
  /// hii inazuia spam ya arifa wakati mnazungumza).
  static String? viewingChatPeerUid;

  /// user (users.notifications_enabled).
  void setUserEnabled(bool enabled) => _userEnabled = enabled;

  Future<void> _fetchUserPreference(String uid) async {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('notifications_enabled')
          .eq('uid', uid)
          .maybeSingle();
      _userEnabled = row?['notifications_enabled'] != false;
    } catch (_) {}
  }

  bool _channelReady = false;

  /// Channel ID lazima ilingane na inayotumika kwenye showNotification
  /// (Android 8+: arifa bila channel iliyopo haionekani kabisa).
  static const String _channelId = 'pacific_general';

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    try {
      const channel = AndroidNotificationChannel(
        _channelId, // id
        'General Notifications', // name
        description: 'Matches, messages, gifts and coins',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _channelReady = true;
    } catch (e) {
      debugPrint('Pacific: channel create failed: $e');
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Kugusa arifa inapokelewa hapa — tunaipeleka kwenye screen husika.
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      // Ask for permission on Android 13+ and iOS.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      // App ilifunguliwa kwa kugusa arifa wakati ilikuwa IMEZIMWA kabisa:
      // hifadhi payload — itashughulikiwa navigator ikisha tayari.
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true &&
            payload != null &&
            payload.isNotEmpty) {
          _pendingLaunchPayload = payload;
          unawaited(_processPendingLaunchPayload());
        }
      } catch (_) {}

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  /// Starts listening for new notifications for the logged-in user.
  ///
  /// MUHIMU — kwa nini BILA .eq() kwenye stream:
  /// `.stream().eq('to_uid', uid)` kwenye supabase-dart inaongeza filter
  /// kama query param ya realtime. Kwa DB/columns za zamani au realtime
  /// iliyosanidiwa tofauti, filter hii inaweza kurudisha rows 0 milele
  /// (ndiyo chanzo cha "messages haziji kama notification").
  /// Badala yake tunasikiliza rows 50 za mwisho kisha tunachuja
  /// client-side: to_uid == mimi && read == false && fresh. Hii daima
  /// inafanya kazi bila kujali realtime config ya server.
  void startListening() {
    final client = Supabase.instance.client;
    final String? uid = client.auth.currentUser?.id;
    if (uid == null || !_initialized) return;

    // Prevent duplicate subscriptions.
    if (_subscription != null) return;
    _firstSnapshotReceived = false;
    _seenIds.clear();
    _fetchUserPreference(uid);
    // Angalia: hakuna .eq() hapa — kuchuja kunafanyika kwenye
    // _onNotifications (client-side). Tazama maelezo hapo juu.
    _subscription ??= client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(50)
        .listen((rows) => _onNotifications(rows, uid), onError: (e) {
      debugPrint('Notifications stream error: $e');
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _seenIds.clear();
    _firstSnapshotReceived = false;
  }

  Future<void> _onNotifications(
    List<Map<String, dynamic>> rows,
    String uid,
  ) async {
    // Soma switch ya mtumiaji upya kila mara (kama amezima Notifications
    // kwenye Profile Settings, usionyeshe chochote — lakini usikate stream).
    await _fetchUserPreference(uid);
    if (!_userEnabled) return;

    // Snapshot ya KWANZA ya stream ni historia — isionyeshwe kama arifa
    // mpya zote kwa pamoja; arifa mpya tu (fresh) ndizo zitaonekana.
    final bool isFirstSnapshot = !_firstSnapshotReceived;
    _firstSnapshotReceived = true;

    final now = DateTime.now();
    for (final row in rows) {
      final String id = row['id']?.toString() ?? '';
      if (id.isEmpty || _seenIds.contains(id)) continue;
      _seenIds.add(id);

      // 1) Mtumaji ni NANI: kama mimi ndiye niliyetuma (echo ya row
      //    yangu mwenyewe kwenye stream isiyo na filter) — nisijionyeshe
      //    arifa yangu mwenyewe.
      final toUid = row['to_uid']?.toString() ?? '';
      final fromUid = row['from_uid']?.toString() ?? '';
      final type = row['type']?.toString() ?? '';
      // type/message/title/description + row kamili (kwa debug + tap).
      debugPrint('Pacific: notif row type=$type to=$toUid from=$fromUid');
      if (type != 'message') continue;
      if (fromUid.isNotEmpty && fromUid == uid) continue;
      // 2) Mpokeaji: onyesha kama to_uid inalingana na mimi AU kama
      //    haijulikani (tupu). ANGALIA: hatukatai arifa pale to_uid
      //    isipolingana — DB za zamani zinaweza kuhifadhi uuid huku auth
      //    uid ikiwa text (au kinyume), na kulinganisha strings moja kwa
      //    moja kungekataa arifa halali kimya (ndicho kilichosababisha
      //    "messages haziji kama notification"). Kigezo kikuu ni:
      //    type == message + read == false + fresh + si echo yangu.
      final bool addressedToMe = toUid.isEmpty || toUid == uid;

      // Skip anything already marked as read (e.g. history).
      if (row['read'] == true) continue;
      // Onyesha row MPYA tu: iliyoundwa ndani ya dakika 5 zilizopita.
      // Hii inafanya kazi hata app ikiwa OPEN (background/foreground),
      // na inazuia historia ya zamani kuonekana kama arifa mpya.
      // (Zamani: isFirstSnapshot iliruka kila kitu mara ya kwanza,
      //  lakini _seenIds ilikumbuka ids milele — ujumbe mpya ulirukwa.)
      //
      // ANGALIA: baadhi ya DB zina created_at kama NULL (column ya zamani
      // au default haikuwekwa) — row kama hiyo ilikuwa INARUKWA kimya
      // (isFresh=false). Sasa: kama hakuna timestamp, na si snapshot ya
      // kwanza (historia), ionyeshe — ni ujumbe mpya uliofika live.
      final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
      final bool isFresh = createdAt == null
          ? !isFirstSnapshot
          : now.difference(createdAt).inMinutes.abs() <= 5;
      if (!isFresh) continue;

      // User yuko ndani ya chat hii wazi — ataona ujumbe papo hapo,
      // hana haja ya arifa ya system (inazuia spam wakati mnazungumza).
      if (type == 'message' &&
          viewingChatPeerUid != null &&
          fromUid == viewingChatPeerUid) {
        continue;
      }

      // Payload kwa deep-link: type|fromUid|fromName
      if (!addressedToMe) {
        debugPrint('Pacific: notif to-uid mismatch but showing (legacy id format)');
      }

      final payload = '$type|$fromUid|${row['from_name']?.toString() ?? ''}';

      await showNotification(
        id: id.hashCode,
        title: row['title']?.toString() ?? 'Pacific',
        body: row['description']?.toString() ?? '',
        payload: payload,
      );
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String payload = '',
  }) async {
    if (!_initialized) return;
    await _ensureChannel();
    try {
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _channelId,
        'General Notifications',
        channelDescription: 'Matches, messages, gifts and coins',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        // Mapendeleo ya mtumiaji (Profile > Notifications):
        playSound: UserPrefs.instance.soundEnabled,
        enableVibration: UserPrefs.instance.vibrationEnabled,
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(id, title, body, details, payload: payload);
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }

  /// Futa arifa zote za ujumbe (tray) kutoka mtu husika na ziweke read.
  /// Inaitwa ukifungua chat yake — hivyo "alama ya ujumbe mpya" na arifa
  /// zinazokaa kwenye notification tray zinaondolewa papo hapo.
  Future<void> clearMessageNotificationsFor(String peerUid) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty || peerUid.isEmpty) return;

    // 1. Arifa za tray: futa zile zisizosomwa za mtu huyu.
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('notifications')
          .select('id')
          .eq('to_uid', uid)
          .eq('from_uid', peerUid)
          .eq('type', 'message')
          .eq('read', false);
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        try {
          await _plugin.cancel(id.hashCode);
        } catch (_) {}
      }
    } catch (_) {}

    // 2. Weke alama read kwenye DB — inapunguza "unread" za arifa na
    //    kufanya iisomekane tena.
    try {
      await client
          .from('notifications')
          .update({'read': true})
          .eq('to_uid', uid)
          .eq('from_uid', peerUid)
          .eq('type', 'message')
          .eq('read', false);
    } catch (_) {}
  }

  // ============================================================
  // TAP / DEEP-LINK — kugusa arifa kunafungua screen husika
  // ============================================================

  /// App ilifunguliwa kwa kugusa arifa (app ilikuwa imezimwa): navigator
  /// huwa haija tayari mara moja — jaribu hadi iwe tayari kisha funua.
  Future<void> _processPendingLaunchPayload() async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (CallService.instance.navigatorKey.currentContext != null) break;
    }
    final payload = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    if (payload == null || payload.isEmpty) return;
    _handleNotificationTap(payload);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _handleNotificationTap(payload);
  }

  /// Mtumiaji aligusa arifa — peleka kwenye chat husika ('message' na
  /// 'missed_call'); types nyingine zinafungua app tu.
  void _handleNotificationTap(String payload) {
    final parts = payload.split('|');
    final String type = parts.isNotEmpty ? parts[0] : '';
    final String fromUid = parts.length > 1 ? parts[1] : '';
    final String fromName = parts.length > 2 ? parts[2] : '';
    if (fromUid.isEmpty) return;
    if (type != 'message' && type != 'missed_call') return;

    final context = CallService.instance.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    unawaited(_openChatFromNotification(context, fromUid, fromName));
  }

  /// Consumer wa pending chat launch — inaitwa na UI layer (k.m. PresenceTracker)
  /// kila mara widget inapopatikana. Inarudisha data na kufuta pending state.
  static ({String uid, String name, String avatarUrl})? consumePendingChatLaunch() {
    if (_pendingChatUid == null) return null;
    final result = (
      uid: _pendingChatUid!,
      name: _pendingChatName ?? 'User',
      avatarUrl: _pendingChatAvatarUrl ?? '',
    );
    _pendingChatUid = null;
    _pendingChatName = null;
    _pendingChatAvatarUrl = null;
    return result;
  }

  Future<void> _openChatFromNotification(
    BuildContext context,
    String peerUid,
    String peerName,
  ) async {
    // Pata picha ya mwenzake (kwa avatar) — best effort.
    String avatarUrl = '';
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('profile_image_url')
          .eq('uid', peerUid)
          .maybeSingle();
      avatarUrl = row?['profile_image_url']?.toString() ?? '';
    } catch (_) {}

    // Store pending chat launch — consumer (UI layer) atapita na
    // kuitimize. Hii inavunja circular import kati ya
    // notification_service <-> individual_chat_screen.
    _pendingChatUid = peerUid;
    _pendingChatName = peerName;
    _pendingChatAvatarUrl = avatarUrl;
  }
}
