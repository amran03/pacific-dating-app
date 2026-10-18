import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_service.dart';
import 'user_prefs.dart';

// ============================================================
// NOTIFICATION SERVICE — system (tray) notifications + navigation.
// ============================================================
//
// MESSAGE/MATCH FLOW (works with the app open):
//   A sends B a message (individual_chat_screen._sendMessage)
//     -> INSERT messages (chat between A and B)
//     -> INSERT notifications (to_uid = B, from_uid = A)
//   B (this service):
//     -> the notifications stream sees the new row (realtime)
//     -> shows a SYSTEM notification (tray) with A's name
//     -> tapping it opens A's IndividualChatScreen
//
// PUSH FLOW (works backgrounded / killed — needs Firebase, see below):
//   A sends B a message/call
//     -> INSERT notifications row (same as above)
//     -> Supabase Edge Function `send-push` fans out an FCM data message
//        to every fcm_token stored for B (users.fcm_token)
//   B's device (PushService, registered in main.dart BEFORE runApp):
//     -> FirebaseMessaging.onBackgroundMessage fires even when killed
//     -> shows the SAME local notification channels as the realtime path
//     -> tapping routes via NotificationService.handlePushTap
//
// FIREBASE SETUP (one-time, in the Firebase console):
//   1. Create a Firebase project, add the Android app with
//      applicationId from android/app/build.gradle.kts.
//   2. Download google-services.json into android/app/.
//   3. Add the google-services plugin (see android docs in this repo).
//   4. Deploy supabase/functions/send-push with FCM_PROJECT_ID,
//      FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY secrets.
//   Until then, everything degrades gracefully: foreground realtime
//   notifications keep working; only killed-state delivery needs FCM.
//
// BADGES / COUNT (chat icon + chat list):
//   Count is computed from messages (receiver_id = me, seen = false).
//   Opening a chat marks seen = true so the count clears automatically.
//   Tray notifications are cleared by clearMessageNotificationsFor.
//
// WHY the stream has NO .eq() filters:
//   `.stream().eq('to_uid', uid)` on older supabase-dart versions adds the
//   filter as a realtime query param that can return 0 rows forever when
//   the server realtime config differs. Instead we listen to the last 50
//   rows and filter client-side: to_uid == me && read == false && fresh.
//   This always works regardless of the server realtime config.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firstSnapshotReceived = false; // first snapshot = history
  bool _userEnabled = true; // the user's switch (users.notifications_enabled)
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

  /// Public tap router for FCM pushes (PushService) and any other
  /// background entry point. Routes chat payloads to the chat opener
  /// and call payloads to the pending-call slot consumed by the UI.
  void handlePushTap(String payload) => _handleNotificationTap(payload);

  /// FCM foreground path: show a chat/message banner through the same
  /// general channel used by the realtime listener.
  Future<void> showFromPush({
    required String title,
    required String body,
    required String payload,
  }) async {
    // Mzunguko wa FCM wa mbele (foreground) — heshimu switch ya
    // Settings > Notifications papo hapo (UserPrefs ni cache halisi).
    if (!UserPrefs.instance.notificationsEnabled) return;

    // Payload: type|fromUid|fromName
    final parts = payload.split('|');
    final String type = parts.isNotEmpty ? parts[0] : '';
    final String fromUid = parts.length > 1 ? parts[1] : '';

    // User yuko ndani ya chat na mzunguko huu — njia ya realtime imezima
    // arifa kwa makusudi (inazuia spam wakati mnazungumza); FCM isikate
    // mpango huo.
    if (type == 'message' &&
        viewingChatPeerUid != null &&
        fromUid == viewingChatPeerUid) {
      return;
    }

    // Zuia marudiano: kila ujumbe unaingiza row kwenye notifications
    // (realtime inaonyesha) NA kinafanya FCM push — bila kizuizi hiki
    // mtumiaji mwenye app wazi anapata arifa mbili kwa ujumbe mmoja.
    if (!_claimShow('$type|$fromUid|$title|$body')) return;

    await showNotification(
      id: payload.hashCode,
      title: title,
      body: body,
      payload: payload,
    );
  }

  // ============================================================
  // DEDUPE — mtiririko wa realtime na mtiririko wa FCM foreground
  // huona ujumbe ULE ULE (title/body/from_uid zinafanana kabisa).
  // Cache hii ndiyo hufanya ujumbe mmoja usionyeshwe mara mbili.
  // ============================================================
  static final Map<String, DateTime> _recentlyShown = {};

  /// Rudisha true mara ya KWANZA kwa kila key ndani ya sekunde 15;
  /// false kama tayari imeonyeshwa hivi karibuni.
  static bool _claimShow(String key) {
    final now = DateTime.now();
    _recentlyShown.removeWhere((_, at) => now.difference(at).inSeconds > 15);
    final prev = _recentlyShown[key];
    if (prev != null && now.difference(prev).inSeconds <= 15) return false;
    _recentlyShown[key] = now;
    return true;
  }

  Future<void> _fetchUserPreference(String uid) async {
    // Njia ya haraka: UserPrefs tayari ina cache ya notifications_enabled
    // (imebadilishwa mara moja na Settings) — hakuna safari ya DB kila
    // snapshot. DB ni fallback pale cache bado haijapakia.
    if (UserPrefs.instance.isLoaded) {
      _userEnabled = UserPrefs.instance.notificationsEnabled;
      return;
    }
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

  // ---- High-priority incoming-call channel (full-screen intent) ----
  static const String _callChannelId = 'pacific_calls_high_priority';
  bool _callChannelReady = false;

  Future<void> _ensureCallChannel() async {
    if (_callChannelReady) return;
    try {
      const channel = AndroidNotificationChannel(
        _callChannelId,
        'Incoming calls',
        description: 'Rings for incoming voice and video calls.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _callChannelReady = true;
    } catch (_) {}
  }

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

      // Notification taps are routed to the relevant screen here.
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            _onBackgroundNotificationResponse,
      );

      // Pre-create both channels so Android 8+ always has them, and ask
      // for permission on Android 13+ and iOS.
      await _ensureChannel();
      await _ensureCallChannel();

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

      // App iko BACKGROUND (realtime inaweza kupokea wakati process bado
      // iko hai) — FCM ndio itaonyesha kupitia background isolate (cache
      // ya dedupe haishiriki kati ya isolates). Hapa tunazuia marudiano:
      // arifa moja tu itaonekana bila kujali hali ya app.
      final String? lifecycle = WidgetsBinding.instance.lifecycleState?.name;
      if (lifecycle != null && lifecycle != 'resumed') continue;

      final payload = '$type|$fromUid|${row['from_name']?.toString() ?? ''}';
      final title = row['title']?.toString() ?? 'Pacific';
      final body = row['description']?.toString() ?? '';

      // Dedupe: kama FCM foreground tayari imeonyesha ujumbe huu hivi
      // karibuni (au kinyume chake), usionyeshe mara ya pili.
      if (!_claimShow('$type|$fromUid|$title|$body')) continue;

      await showNotification(
        id: id.hashCode,
        title: title,
        body: body,
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
        // User preferences (Profile > Notifications):
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

  // ---- Pending incoming call (rings from another app / killed) ----
  static ({String callId, bool isVideo, String name, String uid})?
      _pendingIncomingCall;

  /// Consumed once by the UI layer to open CallScreen as callee.
  static ({String callId, bool isVideo, String name, String uid})?
      consumePendingIncomingCall() {
    final c = _pendingIncomingCall;
    _pendingIncomingCall = null;
    return c;
  }

  /// Parses `call|<callId>|<audio|video>|<callerName>|<callerUid>`.
  static ({String callId, bool isVideo, String name, String uid})?
      parseCallPayload(String payload) {
    final parts = payload.split('|');
    if (parts.length < 5 || parts[0] != 'call') return null;
    if (parts[1].isEmpty) return null;
    return (
      callId: parts[1],
      isVideo: parts[2] == 'video',
      name: parts[3].isEmpty ? 'Unknown' : parts[3],
      uid: parts[4],
    );
  }

  int _callNotifId(String callId) => callId.hashCode;

  /// WhatsApp-style ringing notification: max importance, full-screen
  /// intent (rings over other apps / lock screen), sound + vibration,
  /// with Answer / Decline actions routing into CallScreen.
  Future<void> showIncomingCall({
    required String title,
    required String body,
    required String payload,
  }) async {
    final call = parseCallPayload(payload);
    if (call == null) return;
    _pendingIncomingCall = call;
    if (!_initialized) return;
    await _ensureCallChannel();
    try {
      final android = AndroidNotificationDetails(
        _callChannelId,
        'Incoming calls',
        channelDescription: 'Rings for incoming voice and video calls.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        autoCancel: false,
        ongoing: true,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'answer_call',
            'Answer',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'decline_call',
            'Decline',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
      final details = NotificationDetails(android: android);
      await _plugin.show(
        _callNotifId(call.callId),
        title,
        body,
        details,
        payload: payload,
      );
    } catch (_) {}
  }

  /// Cancels the ringing notification once answered / declined / timed out.
  Future<void> cancelIncomingCall(String callId) async {
    try {
      await _plugin.cancel(_callNotifId(callId));
    } catch (_) {}
  }


  /// Background-isolate entry for incoming-call pushes (FCM handler has
  /// no Supabase access — it just shows the ringing notification; tapping
  /// it reopens the app where the pending-call slot takes over).
  static Future<void> showIncomingCallBackground({
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const settings = InitializationSettings(android: androidSettings);
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings);
      const channel = AndroidNotificationChannel(
        _callChannelId,
        'Incoming calls',
        description: 'Rings for incoming voice and video calls.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      const android = AndroidNotificationDetails(
        _callChannelId,
        'Incoming calls',
        channelDescription: 'Rings for incoming voice and video calls.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        autoCancel: false,
        ongoing: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'answer_call',
            'Answer',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'decline_call',
            'Decline',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
      const details = NotificationDetails(android: android);
      await plugin.show(
        payload.hashCode,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (_) {}
  }

  /// Background-isolate entry for chat/message pushes.
  static Future<void> showChatMessageBackground({
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');
      const settings = InitializationSettings(android: androidSettings);
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings);
      const channel = AndroidNotificationChannel(
        _channelId,
        'General Notifications',
        description: 'Matches, messages, gifts and coins',
        importance: Importance.high,
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      const android = AndroidNotificationDetails(
        _channelId,
        'General Notifications',
        channelDescription: 'Matches, messages, gifts and coins',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );
      const details = NotificationDetails(android: android);
      await plugin.show(
        payload.hashCode,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (_) {}
  }


  // ============================================================
  // TAP / DEEP-LINK — tapping a notification opens its screen.
  // ============================================================

  /// The app was opened by tapping a notification while fully closed:
  /// the navigator is not ready immediately — retry until it is.
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
    _handleNotificationTap(payload, actionId: response.actionId);
  }

  /// Background-tap entry (plugin callback while the app process was
  /// dead). Routes the same way as the foreground tap.
  static void _onBackgroundNotificationResponse(
    NotificationResponse response,
  ) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    NotificationService.instance._handleNotificationTap(
      payload,
      actionId: response.actionId,
    );
  }

  /// A notification was tapped — route chat payloads ('message' /
  /// 'missed_call') to the chat opener and call payloads ('call|…')
  /// to the pending-call slot consumed by the UI layer so Answer /
  /// Decline from the notification lands in CallScreen.
  void _handleNotificationTap(String payload, {String? actionId}) {
    if (payload.startsWith('call|')) {
      _handleCallTap(payload, actionId: actionId);
      return;
    }
    final parts = payload.split('|');
    final String type = parts.isNotEmpty ? parts[0] : '';
    final String fromUid = parts.length > 1 ? parts[1] : '';
    final String fromName = parts.length > 2 ? parts[2] : '';
    if (fromUid.isEmpty) return;
    if (type != 'message' && type != 'missed_call') return;

    // Stash BILA kizuizi cha navigator context: `_openChatFromNotification`
    // haitegemei context — inachukua avatar tu. Kizuizi cha zamani
    // kilipoteza tap za barua pepe wakati app bado iko kwenye splash/
    // cold-start (context bado haikuwa tayari). Mzunguko wa PresenceTracker
    // ndio hutafuta stash hii na kufungua chat app ikiwa tayari.
    unawaited(_openChatFromNotification(fromUid, fromName));
  }

  /// A ringing-call notification was tapped (or an Answer/Decline action
  /// pressed): stash the call for the UI layer and clear the ring. Plain
  /// taps and 'answer_call' open CallScreen as callee (which sends
  /// 'accept' and starts media so audio/video is already connecting);
  /// 'decline_call' only logs a missed call for the caller.
  void _handleCallTap(String payload, {String? actionId}) {
    final call = parseCallPayload(payload);
    if (call == null) return;
    unawaited(cancelIncomingCall(call.callId));
    if (actionId == 'decline_call') {
      // Mtumiaji alikataa — ondoa stash ili consumer (PresenceTracker)
      // isifungue CallScreen baada ya kukataa.
      _pendingIncomingCall = null;
      try {
        final me = Supabase.instance.client.auth.currentUser;
        unawaited(CallService.logMissedCall(
          toUid: me?.id ?? '',
          fromUid: call.uid,
          fromName: call.name,
          isVideo: call.isVideo,
          declined: true,
        ));
      } catch (_) {}
      return;
    }
    // Plain tap or 'answer_call' — the UI consumes this and pushes
    // CallScreen (incoming). showIncomingCall already stashed it; keep
    // the stash fresh in case this tap arrived first.
    _pendingIncomingCall = call;
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
