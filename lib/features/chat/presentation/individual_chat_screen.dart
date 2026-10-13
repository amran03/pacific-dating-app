import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/services/storage_service.dart';

import 'package:pacific_dating_app/features/profile/presentation/public_profile_screen.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';
import 'package:pacific_dating_app/features/chat/presentation/widgets/gift_modal_bottom_sheet.dart';
import 'package:pacific_dating_app/features/chat/presentation/widgets/voice_note_bubble.dart';
import 'package:pacific_dating_app/core/services/presence_service.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/core/services/notification_service.dart';
import 'package:pacific_dating_app/core/services/push_sender.dart';
import 'package:pacific_dating_app/core/services/user_prefs.dart';
import 'package:pacific_dating_app/core/widgets/heart_loader.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/localization/app_language.dart';
// ZEGO 1-on-1 voice & video call invitations.
// zego_uikit (ZegoUIKitUser, ButtonIcon) haiko tena kwenye export ya
// prebuilt_call 4.17+ — import moja kwa moja.
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:pacific_dating_app/core/services/zego_call_service.dart';

import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

class IndividualChatScreen extends StatefulWidget {
  final ChatModel chat;

  const IndividualChatScreen({
    super.key,
    required this.chat,
  });

  @override
  State<IndividualChatScreen> createState() =>
      _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController =
  TextEditingController();

  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;

  final ImagePicker _picker = ImagePicker();

  User? get currentUser => Supabase.instance.client.auth.currentUser;

  AppLanguage get _lang => AppLanguage.instance;

  String? _chatId;

  // ---- CACHED STREAMS (background refresh without full-page rebuild) ----
  // Supabase `.stream()` creates a NEW subscription every time it is called.
  // The old code built these inline inside build()/StreamBuilders, so EVERY
  // setState (typing, presence heartbeat, seen-write) recreated the streams,
  // re-fired `ConnectionState.waiting` and rebuilt the WHOLE Scaffold
  // (AppBar blur + list + input bar all flickered). By creating each stream
  // ONCE in initState and reusing the same instance, only the small
  // StreamBuilder that listens to it rebuilds — the rest of the page stays
  // put and new messages slide in via the background list update.
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  Stream<List<Map<String, dynamic>>>? _typingRoomStream;
  Stream<Map<String, dynamic>?>? _presenceStream;

  // Seen-receipt bookkeeping that must NEVER setState during build.
  bool _seenFrameScheduled = false;
  int _renderedMessageCount = 0;

  // Newest message is at offset 0 (ListView reverse:true).
  final ScrollController _scrollController = ScrollController();

  bool _isRecording = false;

  // ValueNotifier badala ya setState — inapunguza rebuilds za ukurasa mzima
  // (WhatsApp-style smooth typing).
  final ValueNotifier<bool> _isUploadingMedia = ValueNotifier(false);
  final ValueNotifier<bool> _isSendingMessage = ValueNotifier(false);

  // Chat lock state — track whether chat is unlocked for this session.
  StreamSubscription<void>? _playerCompleteSubscription;

  // ---- CHAT LOCK (coin gate) ----
  // Chat inaonekana imefungwa kama mwenzake ameweka bei > 0 NA bado
  // hujalipа. Ukilipa, unlocked_by inahifadhiwa DB -> haifungwi TENA
  // (milele), na overlay inatoweka kabisa.
  bool _chatLocked = false;
  int _unlockPrice = 0;
  bool _unlocking = false;

  // ---- Typing indicator (Supabase-backed, throttled writes) ----
  Timer? _typingClearTimer;
  DateTime? _lastTypingWrite;

  // ---- Smooth chat: entrance animation bookkeeping (post-frame only) ----

  // ---- Recording pulse animation ----
  late final AnimationController _recordingPulse;

  @override
  void initState() {
    super.initState();

    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    _recordingPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 0.5,
    );

    final user = currentUser;

    if (user != null) {
      final ids = [user.id, widget.chat.id]..sort();
      _chatId = ids.join('_');
    }

    // Build every realtime stream ONCE so later setStates (typing box,
    // recording flag, lock check) reuse the same subscription and only the
    // tiny StreamBuilder listening to it rebuilds.
    if (_chatId != null && user != null) {
      final client = Supabase.instance.client;
      _messagesStream ??= client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('chat_id', _chatId!)
          .order('created_at', ascending: false);
      _typingRoomStream ??= client
          .from('chat_rooms')
          .stream(primaryKey: ['id'])
          .eq('id', _chatId!);
      _presenceStream ??=
          PresenceService.streamPeerPresence(widget.chat.id);
    }

    _messageController.addListener(_onMessageChanged);

    // Mark all unread messages from the peer as seen when opening the chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Arifa za 'message' kutoka mwenzake huyu hazionyeshwi tunapokuwa
      // ndani ya chat hii — tunaona ujumbe papo hapo.
      NotificationService.viewingChatPeerUid = widget.chat.id;
      _markMessagesAsSeen();
      _markPeerNotificationsAsRead();
      _checkChatLockStatus();
    });

    _playerCompleteSubscription =
        _audioPlayer.onPlayerComplete.listen((_) {});
  }

  /// Checks if the chat is locked and sets _chatLocked accordingly.
  ///
  /// Lock logic:
  ///  - Mwenzake akiwa na `chat_unlock_price > 0` NA hujalipa -> imefungwa.
  ///  - Ukiwa tayari kwenye `chat_rooms.unlocked_by` -> haifungwi TENA.
  ///  - Bei 0 -> bure, hairuhusu kulock.
  Future<void> _checkChatLockStatus() async {
    final user = currentUser;
    if (user == null || _chatId == null) return;

    try {
      final chatRoom = await Supabase.instance.client
          .from('chat_rooms')
          .select()
          .eq('id', _chatId!)
          .maybeSingle();

      final List<dynamic> unlockedBy =
          (chatRoom?['unlocked_by'] as List<dynamic>?) ?? const [];

      // Ukiwa umelipa mara moja — chat inabaki wazi MILELE.
      if (unlockedBy.contains(user.id)) {
        if (mounted) setState(() => _chatLocked = false);
        return;
      }

      final otherUser = await Supabase.instance.client
          .from('users')
          .select('chat_unlock_price')
          .eq('uid', widget.chat.id)
          .maybeSingle();

      final int price = (otherUser?['chat_unlock_price'] ?? 0) as int;

      if (mounted) {
        setState(() {
          _unlockPrice = price;
          _chatLocked = price > 0;
        });
      }
    } catch (e) {
      debugPrint('Error checking chat lock status: $e');
    }
  }

  /// User ananunua kufungua chat to coins. Baada ya malipo,
  /// overlay inatoweka MILELE (DB ina `unlocked_by`) — hakuna lock tena.
  Future<void> _payAndUnlockChat() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);

    try {
      await MatchmakingService().payAndUnlockChat(widget.chat.id);
      if (!mounted) return;
      setState(() {
        _unlocking = false;
        _chatLocked = false;
      });
      _showMessage(
        'Chat unlocked! You can start chatting now 🎉',
        backgroundColor: AppColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _unlocking = false);
      final String msg = e.toString().contains('INSUFFICIENT_COINS')
          ? 'You do not have enough Pacific Coins. Please buy some first.'
          : 'Failed to unlock chat. Please try again.';
      _showMessage(msg, backgroundColor: AppColors.error);
    }
  }
  /// Overlay ya lock — inaonekana juu ya chat kama bado haijalipwa.
  /// Ina kitufe cha kulipia to coins; ikilipwa inatoweka kabisa.
  Widget _buildChatLockOverlay(bool isLuxury, Color accentColor) {
    // FIXED palette: classic light overlay for everyone (flag/params kept
    // only so call-sites don't churn; they are intentionally unused).
    const Color fg = Colors.black87;
    const Color subFg = Colors.black54;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.coinGold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.coinGold.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: AppColors.coinGoldDark,
                size: 46,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Chat Imefungwa',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.chat.name} charges a one-time fee to unlock this conversation. '
                  'Pay ONCE — the chat stays open forever!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: subFg),
            ),
            const SizedBox(height: 22),
            if (_unlocking)
              const HeartLoader(size: 46)
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.coinGold.withValues(alpha: 0.15),
                  borderRadius: AppRadius.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: AppColors.coinGoldDark,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_unlockPrice Coins',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.coinGoldDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _payAndUnlockChat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.md,
                    ),
                  ),
                  child: Text(
                    'Unlock to $_unlockPrice Coins',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }



  void _onMessageChanged() {
    if (!mounted) return;
    // PERF (WhatsApp-smooth): HATUFANYI setState ya ukurasa mzima kila
    // keystroke â€” kitufe cha send kinasikiliza controller yenyewe kupitia
    // ValueListenableBuilder, hivyo kuandika message hakirefreshi page.
    // (Backdrops/Filters hazirebuildi tena wakati wa typing.)
    _updateTypingStatus();
  }

  // ============================================================
  // TYPING STATUS (peer sees "typing..." bubble)
  // Writes are throttled to at most one ping every 2 seconds and
  // auto-cleared 3 seconds after typing stops.
  // ============================================================

  void _updateTypingStatus() {
    final uid = currentUser?.id;
    final chatId = _chatId;
    if (chatId == null || uid == null) return;

    // User amezima "Typing Indicator" — tusimwonyeshe mwenzake.
    if (!UserPrefs.instance.typingIndicatorEnabled) return;

    if (_messageController.text.trim().isEmpty) {
      _lastTypingWrite = null;
      _typingClearTimer?.cancel();
      _clearTypingStatus(uid);
      return;
    }

    final now = DateTime.now();
    if (_lastTypingWrite == null ||
        now.difference(_lastTypingWrite!) >= const Duration(seconds: 2)) {
      _lastTypingWrite = now;
      // Schema ya chat_rooms ina column moja ya 'typing' (uuid) — tunaandika
      // uid yetu; mwenzake anaiona kupitia realtime stream na kujua sisi
      // tunaandika. (Column ya 'typing_<uid>' haipo kwenye schema.)
      Supabase.instance.client
          .from('chat_rooms')
          .update({
        'typing': uid,
      })
          .eq('id', chatId)
          .catchError((_) {});
    }

    _typingClearTimer?.cancel();
    _typingClearTimer = Timer(const Duration(seconds: 3), () {
      _lastTypingWrite = null;
      _clearTypingStatus(uid);
    });
  }

  void _clearTypingStatus(String uid) {
    final chatId = _chatId;
    if (chatId == null) return;

    Supabase.instance.client
        .from('chat_rooms')
        .update({
      'typing': null,
    })
        .eq('id', chatId)
        .catchError((_) {});
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();

    _typingClearTimer?.cancel();
    _recordingPulse.dispose();

    // Best-effort: clear our typing flag when leaving the chat.
    final uid = currentUser?.id;
    if (uid != null) {
      _clearTypingStatus(uid);
    }

    // Tuliwa tena ndani ya chat hii — arifa za mwenzake ziweze kuonekana.
    if (NotificationService.viewingChatPeerUid == widget.chat.id) {
      NotificationService.viewingChatPeerUid = null;
    }

    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();

    _scrollController.dispose();

    _audioRecorder.dispose();
    _audioPlayer.dispose();

    // Dispose ValueNotifiers
    _isUploadingMedia.dispose();
    _isSendingMessage.dispose();

    super.dispose();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _showMessage(
      String message, {
        Color? backgroundColor,
      }) {
    if (!mounted) return;

    showAppNotification(context, message, color: backgroundColor);
  }

  bool _isValidUrl(String? url) {
    if (url == null) return false;

    final value = url.trim();

    return value.isNotEmpty &&
        (value.startsWith('http://') ||
            value.startsWith('https://'));
  }

  // ============================================================
  // VOICE RECORDING
  // ============================================================

  // ============================================================
  // READ RECEIPTS
  // ============================================================

  /// Marks all unread messages sent by the other person as "seen"
  /// when this chat screen is open (WhatsApp-style read receipts).
  ///
  /// MUHIMU: hii ni LAZIMA ifanyike kila mara chat inapofunguliwa —
  /// hata kama mtumiaji amezima "Read Receipts". Sababu: badge ya count
  /// (icon ya Chat + chat list) inahesabu messages zenye seen=false.
  /// Tukiruka UPDATE kwa sababu ya privacy switch, count haiondoki kamwe.
  /// Privacy switch INAHESHIMIWA kwa blue ticks (✔✔ zinazoonekana na
  /// mwenzake) — tazama [_markAsSeen]/[_flushSeenUpdates] chini.
  ///
  /// Kwa hiyo: seen= true inaandikwa DB (badge inatoweka), lakini kama
  /// read receipts zimezimwa, _markAsSeen (ticks) HAZITUMWI — mwenzake
  /// haoni kuwa umesoma. Hii ni tofauti kati ya "locally read" na
  /// "receipt shown to peer".
  Future<void> _markMessagesAsSeen() async {
    final user = currentUser;
    if (user == null || _chatId == null) return;

    try {
      await Supabase.instance.client
          .from('messages')
          .update({
        'seen': true,
        // Tarehe kamili ya kusoma — kwa ajili ya historia + kuthibitisha
        // kuwa badge ya unread inapungua pale UJUMBE unaposomwa, sio
        // pale orodha ya messages inapofunguliwa.
        'seen_at': DateTime.now().toIso8601String(),
      })
          .eq('chat_id', _chatId!)
          .eq('receiver_id', user.id)
          .eq('seen', false);
    } catch (e) {
      // FALLBACK (DB za zamani bila column ya seen_at): seen bado
      // LAZIMA iandikwe — vinginevyo badge ya unread haiondoki kamwe.
      try {
        await Supabase.instance.client
            .from('messages')
            .update({'seen': true})
            .eq('chat_id', _chatId!)
            .eq('receiver_id', user.id)
            .eq('seen', false);
      } catch (e2) {
        debugPrint('Pacific: mark-seen failed: $e2');
      }
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (!mounted) return;

    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();

        if (!mounted) return;

        _recordingPulse.stop();

        setState(() {
          _isRecording = false;
        });

        if (path != null && path.trim().isNotEmpty) {
          await _sendMessage(
            type: 'audio',
            mediaUrl: path,
            text: 'ðŸŽ™ï¸ Voice Note',
          );
        }

        return;
      }

      final status = await Permission.microphone.request();

      if (!mounted) return;

      if (!status.isGranted) {
        _showMessage(
          "Please allow microphone access to record audio.",
        );
        return;
      }

      final hasPermission =
      await _audioRecorder.hasPermission();

      if (!hasPermission) {
        if (!mounted) return;

        _showMessage(
          "Microphone permission haijaruhusiwa.",
        );
        return;
      }

      final directory =
      await getApplicationDocumentsDirectory();

      final filePath =
          '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
        ),
        path: filePath,
      );

      if (!mounted) return;

      _recordingPulse.repeat(reverse: true);

      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      if (!mounted) return;

      _recordingPulse.stop();

      setState(() {
        _isRecording = false;
      });

      _showMessage(
        "Failed to start voice recording.",
      );
    }
  }

  // ============================================================
  // AUDIO PLAYER
  // ============================================================

  // ============================================================
  // IMAGE PICKER
  // ============================================================

  Future<void> _pickImage(ImageSource source) async {
    if (_isUploadingMedia.value || _isSendingMessage.value) {
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (!mounted || image == null) return;

      await _sendMessage(
        type: 'image',
        mediaUrl: image.path,
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        "Failed to pick photo.",
      );
    }
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> _sendMessage({
    required String type,
    String? text,
    String? mediaUrl,
  }) async {
    final user = currentUser;
    final chatId = _chatId;

    if (user == null || chatId == null) {
      _showMessage(
        "Your account was not found. Please log in again.",
      );
      return;
    }

    if (_isSendingMessage.value) return;

    final controllerText =
    _messageController.text.trim();

    if (type == 'text' &&
        controllerText.isEmpty &&
        (mediaUrl == null || mediaUrl.trim().isEmpty)) {
      return;
    }

    final messageText =
        text ?? controllerText;

    _messageController.clear();

    String finalMediaUrl =
        mediaUrl?.trim() ?? '';

    if (finalMediaUrl.isNotEmpty &&
        !_isValidUrl(finalMediaUrl)) {
      if (!mounted) return;

      _isUploadingMedia.value = true;

      try {
        final file = File(finalMediaUrl);

        if (!await file.exists()) {
          throw Exception(
            'Selected media file does not exist.',
          );
        }

        final extension =
        type == 'audio' ? 'm4a' : 'jpg';

        final storageService = StorageService();
        finalMediaUrl = await storageService.uploadChatMedia(chatId, file, extension) ?? '';

        if (finalMediaUrl.isEmpty) throw Exception('Upload failed');
      } catch (e) {
        if (!mounted) return;

        _isUploadingMedia.value = false;

        _showMessage(
          "Failed to upload file.",
        );

        return;
      }

      if (!mounted) return;

      _isUploadingMedia.value = false;
    }

    if (!mounted) return;

    _isSendingMessage.value = true;

    try {
      final messageData = <String, dynamic>{
        'chat_id': chatId,
        'sender_id': user.id,
        'receiver_id': widget.chat.id,
        'type': type,
        'content': messageText,
        'media_url': finalMediaUrl,
        'created_at': DateTime.now().toIso8601String(),
        'seen': false,
      };

      await Supabase.instance.client
          .from('messages')
          .insert(messageData);

      String previewText;

      switch (type) {
        case 'image':
          previewText = 'ðŸ“¸ Picha';
          break;

        case 'audio':
          previewText = 'ðŸŽ™ï¸ Ujumbe wa Sauti';
          break;

        default:
          previewText = messageText;
      }

      final participantIds = [
        user.id,
        widget.chat.id,
      ]..sort();

      await Supabase.instance.client
          .from('chat_rooms')
          .upsert({
        'id': chatId,
        'participants': participantIds,
        'last_message': previewText,
        'last_message_at': DateTime.now().toIso8601String(),
      });

      // NOTIFICATION — mfumo wa arifa: mwenzake anapata arifa halisi ya
      // system kwenye kifaa chake (NotificationService inasikiliza table
      // ya notifications kwa realtime na kuionyesha). Ukiguswa, arifa
      // inampeleka moja kwa moja kwenye chat hii (deep-link).
      try {
        final myName = await _fetchMyDisplayName();
        final title = myName.isNotEmpty ? '$myName 💬' : 'New message 💬';
        final desc =
        previewText.isNotEmpty ? previewText : 'Sent you a message';
        await Supabase.instance.client.from('notifications').insert({
          'to_uid': widget.chat.id,
          'from_uid': user.id,
          'from_name': myName,
          'type': 'message',
          'title': title,
          'description': desc,
          'read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
        // FCM push so the peer is reached even when backgrounded/killed.
        // Best-effort — the realtime path above already covers foreground.
        unawaited(PushSender.send(
          toUid: widget.chat.id,
          type: 'message',
          title: title,
          body: desc,
          fromUid: user.id,
          fromName: myName,
        ));
      } catch (e) {
        // Arifa ni best-effort — usivuruge kutuma ujumbe, lakini log
        // ili RLS failures zionekane kwenye console (hapo awali ilikuwa
        // kimya kabisa na tatizo halikuonekana).
        debugPrint('Pacific: notification insert failed: $e');
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        "Failed to send message. Please try again.",
      );
    } finally {
      if (mounted) {
        _isSendingMessage.value = false;
        _isUploadingMedia.value = false;
      }
    }
  }

  // ============================================================
  // NOTIFICATION CLEAR — ukifungua chat, arifa zote za 'message' za
  // mwenzake huyo zinawekwa alama read NA zinafutwa kutoka notification
  // tray (hivyo count kwenye icon ya messages na alama za "ujumbe mpya"
  // hupungua/kutoweka papo hapo).
  // ============================================================

  /// Jina la mtumiaji wa sasa (cached) — linatumika kwenye arifa ya
  /// ujumbe mpya ("Amina 💬"). Linatafutwa mara moja tu kwa session.
  String? _myDisplayName;

  Future<String> _fetchMyDisplayName() async {
    if (_myDisplayName != null) return _myDisplayName!;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('name')
          .eq('uid', currentUser!.id)
          .maybeSingle();
      _myDisplayName = row?['name']?.toString() ?? '';
    } catch (_) {
      _myDisplayName = '';
    }
    return _myDisplayName!;
  }

  /// ============================================================
  /// ZEGO CALL PERMISSIONS — omba camera/mic kabla ya kupiga simu.
  /// ============================================================
  /// Rudisha `true` tu zote zimeruhusiwa; vinginevyo onyesha ujumbe
  /// wazi mtumiaji akikataa na usitume invitation.
  Future<bool> _ensureCallPermissions({required bool isVideo}) async {
    final statuses = await <Permission>[
      Permission.microphone,
      if (isVideo) Permission.camera,
    ].request();

    if (!mounted) return false;

    final micOk = statuses[Permission.microphone]?.isGranted ?? false;
    final camOk = !isVideo || (statuses[Permission.camera]?.isGranted ?? false);

    if (micOk && camOk) return true;

    final denied = <String>[];
    if (!micOk) denied.add('microphone');
    if (isVideo && !(statuses[Permission.camera]?.isGranted ?? false)) {
      denied.add('camera');
    }

    final permanentlyDenied = denied.any((p) {
      final s = p == 'microphone'
          ? statuses[Permission.microphone]
          : statuses[Permission.camera];
      return s?.isPermanentlyDenied ?? false;
    });

    showAppNotification(
      context,
      permanentlyDenied
          ? '${denied.join(' & ')} permission is blocked. Please enable it '
              'in Settings to start calls.'
          : 'Calls need ${denied.join(' & ')} access. Please allow the '
              'permission to continue.',
      type: AppNotificationType.error,
      duration: const Duration(seconds: 5),
    );
    return false;
  }

  void _markPeerNotificationsAsRead() {
    unawaited(
      NotificationService.instance.clearMessageNotificationsFor(
        widget.chat.id,
      ),
    );
  }

  // ============================================================
  // READ RECEIPT (blue ticks ✔✔) — ujumbe wa mwenzake unawekwa alama
  // seen unapoonekana screen (kama bado haujawekwa). Hii ndiyo inayomwonyesha
  // MWENZAKE kuwa umesoma — kwa hiyo INAHESHIMU privacy switch ya
  // "Read Receipts": ukizima, ticks hazitumwi (lakini badge yako mwenyewe
  // bado inatoweka kupitia _markMessagesAsSeen, tazama juu).
  // ============================================================

  /// Pending seen updates collected during a single build cycle;
  /// flushed once per frame to avoid hammering Supabase.
  final List<String> _pendingSeenIds = [];

  void _markAsSeen(
      Map<String, dynamic> rawData,
      List<dynamic> messages,
      String chatId,
      ) {
    final user = currentUser;
    if (user == null) return;

    // Mtumiaji amezima "Read Receipts" — usimtumie mwenzake receipt
    // (blue ticks). Badge yake mwenyewe bado inatoweka kupitia
    // _markMessagesAsSeen — privacy hapa, si count.
    if (!UserPrefs.instance.readReceiptsEnabled) return;

    // Only mark peer's messages (not my own).
    if (rawData['sender_id'] == user.id) return;

    // Already seen — skip.
    if (rawData['seen'] == true) return;

    // In Supabase, the ID is usually part of the rawData
    String? docId = rawData['id']?.toString();

    if (docId == null || _pendingSeenIds.contains(docId)) return;

    _pendingSeenIds.add(docId);

    // Flush on next microtask (deduplicates burst builds).
    if (_pendingSeenIds.length == 1) {
      Future.microtask(_flushSeenUpdates);
    }
  }

  void _flushSeenUpdates() {
    if (_pendingSeenIds.isEmpty || !mounted) return;

    final client = Supabase.instance.client;
    final idsToUpdate = List<String>.from(_pendingSeenIds);
    _pendingSeenIds.clear();

    client
        .from('messages')
        .update({'seen': true, 'seen_at': DateTime.now().toIso8601String()})
        .inFilter('id', idsToUpdate)
        .catchError((_) async {
      // FALLBACK (DB za zamani bila seen_at): seen bado iandikwe.
      try {
        await client
            .from('messages')
            .update({'seen': true})
            .inFilter('id', idsToUpdate);
      } catch (_) {
        // Silently ignore — read receipt is best-effort.
      }
    });
  }

  // ============================================================
  // MEDIA PICKER
  // ============================================================

  void _showMediaPickerOptions() {
    if (_isUploadingMedia.value || _isSendingMessage.value) {
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(30),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 15,
              sigmaY: 15,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius:
                const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceAround,
                  children: [
                    _buildMediaOption(
                      icon: Icons.photo_library_rounded,
                      gradient: const LinearGradient(
                        colors: [
                          Colors.purple,
                          Colors.deepPurpleAccent,
                        ],
                      ),
                      label: "Gallery",
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickImage(
                          ImageSource.gallery,
                        );
                      },
                    ),
                    _buildMediaOption(
                      icon: Icons.camera_alt_rounded,
                      gradient: const LinearGradient(
                        colors: [
                          Colors.orange,
                          Colors.deepOrangeAccent,
                        ],
                      ),
                      label: "Camera",
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _pickImage(
                          ImageSource.camera,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaOption({
    required IconData icon,
    required Gradient gradient,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
  // ============================================================
  // CHAT PALETTE (classic only — single source of truth)
  // ============================================================
  // The old diamond/gold/bronze switch tinted this page per user and is
  // intentionally gone: every chat uses the theme background + the rose
  // AppColors.primaryGradient for MY bubbles.

  // ============================================================
  // PROFILE AVATAR - SAFE
  // ============================================================

  Widget _buildAvatar({
    required String? imageUrl,
    required double radius,
    required bool isLuxury,
    required Color accentColor,
  }) {
    final hasImage = _isValidUrl(imageUrl);

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
          imageUrl!.trim(),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder:
              (context, error, stackTrace) {
            return _fallbackAvatar(
              radius: radius,
              isLuxury: isLuxury,
            );
          },
        )
            : _fallbackAvatar(
          radius: radius,
          isLuxury: isLuxury,
        ),
      ),
    );
  }

  Widget _fallbackAvatar({
    required double radius,
    required bool isLuxury,
  }) {
    // FIXED: neutral grey fallback for everyone (no luxury tint).
    return Container(
      width: radius * 2,
      height: radius * 2,
      color: Colors.grey.shade200,
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.15,
        color: Colors.grey.shade500,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final user = currentUser;
    final chatId = _chatId;

    if (user == null || chatId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F8),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            "User not found.\nPlease log in again.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // No outer user/tier StreamBuilders on purpose: the classic theme never
    // changes from `users` rows, and wrapping the Scaffold in them meant
    // every presence heartbeat (~45s) rebuilt the WHOLE page. The shell
    // below is static and messages/typing/presence refresh in the
    // background via the small cached StreamBuilders.
    //
    // COLOR SYSTEM (single source of truth): AppColors.primaryGradient
    // (#FF4B6E -> #E03355) for MY bubbles + send button, theme
    // scaffoldBackgroundColor for the page, and Colors.white for peer
    // bubbles. isLuxury stays false so all bubbles share one palette.

    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    const accentColor = AppColors.primary;

    const isLuxury = false;

    return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: bgColor,

              appBar: PreferredSize(
                preferredSize:
                const Size.fromHeight(65),
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 12,
                      sigmaY: 12,
                    ),
                    child: AppBar(
                      // FIXED palette: theme surface at 70% — the AppBar
                      // itself never rebuilds (only the tiny presence
                      // StreamBuilder inside the title does).
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.7),
                      elevation: 0,
                      scrolledUnderElevation: 0,

                      leading: IconButton(
                        icon: Icon(
                          Icons
                              .arrow_back_ios_new_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface,
                        ),
                        onPressed: () =>
                            Navigator.pop(context),
                      ),

                      title: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PublicProfileScreen(
                                    uid: widget.chat.id,
                                  ),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            _buildAvatar(
                              imageUrl:
                              widget.chat.avatarUrl,
                              radius: 20,
                              isLuxury: isLuxury,
                              accentColor:
                              accentColor,
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.chat.name,
                                    maxLines: 1,
                                    overflow:
                                    TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontSize: 16,
                                      fontWeight:
                                      FontWeight.bold,
                                    ),
                                  ),

                                  // REAL-TIME ONLINE STATUS (mfano
                                  // WhatsApp): inaonekana "Online" ikiwa
                                  // peer ifanye presence; bila isogwa,
                                  // inaonekana lastSeen.
                                  // CACHED stream: this tiny widget alone
                                  // rebuilds — the page shell stays put.
                                  StreamBuilder<
                                      Map<String, dynamic>?>(
                                    stream: _presenceStream,
                                    builder: (context,
                                        presenceData) {
                                      // Mwenzake akiwa amezima "Onyesha
                                      // Online Status", tunaonyesha neutral
                                      // dot + "offline" bila kufichua
                                      // last_seen yake (privacy).
                                      final peerHidesStatus =
                                          presenceData.data?[
                                          'show_online_status_enabled'] ==
                                              false;
                                      final online = !peerHidesStatus &&
                                          PresenceService.isOnline(
                                            presenceData.data,
                                          );
                                      final dotColor = online
                                          ? AppColors.success
                                          : Colors.grey;
                                      final lastSeenStr = peerHidesStatus
                                          ? null
                                          : presenceData.data?['last_seen'];
                                      final lastSeen = lastSeenStr != null
                                          ? DateTime.tryParse(lastSeenStr)
                                          : null;

                                      return Row(
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: dotColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: dotColor.withValues(
                                                    alpha: 0.5,
                                                  ),
                                                  blurRadius: 6,
                                                  spreadRadius: 1.5,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 5,
                                          ),

                                          Text(
                                            online
                                                ? (_lang.isSwahili
                                                ? 'Online'
                                                : 'Online')
                                                : (lastSeen != null
                                                ? PresenceService
                                                .lastSeenLabel(
                                              lastSeen,
                                              swPrefix:
                                              'zilizopita',
                                            )
                                                : 'offline'),
                                            style: TextStyle(
                                              color: online
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.7),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      actions: [
                        // AUDIO CALL (ZEGO 1-on-1 voice invitation)
                        Container(
                          margin:
                          const EdgeInsets.only(
                            right: 2,
                          ),
                          decoration:
                          BoxDecoration(
                            color: AppColors
                                .primaryDeep
                                .withValues(alpha: 0.12),
                            shape:
                            BoxShape.circle,
                          ),
                          child:
                          ZegoSendCallInvitationButton(
                            invitees: [
                              ZegoUIKitUser(
                                id: ZegoCallService.sanitizeUserId(widget.chat.id),
                                name: widget.chat.name,
                              ),
                            ],
                            isVideoCall: false,
                            resourceID: ZegoCallService.resourceID,
                            buttonSize: const Size(44, 44),
                            borderRadius: 22,
                            icon: ButtonIcon(
                              icon: Icon(
                                Icons.call_rounded,
                                color: AppColors.primaryDeep,
                                size: 21,
                              ),
                            ),
                            // Omba microphonе kabla ya kutuma invitation.
                            onWillPressed: () =>
                                _ensureCallPermissions(isVideo: false),
                            onPressed: (code, message, _) {
                              if (code != '0' && mounted) {
                                showAppNotification(
                                  context,
                                  'Call failed: $message',
                                  type: AppNotificationType.error,
                                );
                              }
                            },
                          ),
                        ),

                        // VIDEO CALL (ZEGO 1-on-1 video invitation)
                        Container(
                          margin:
                          const EdgeInsets.only(
                            right: 2,
                          ),
                          decoration:
                          BoxDecoration(
                            color: AppColors
                                .primaryDeep
                                .withValues(alpha: 0.12),
                            shape:
                            BoxShape.circle,
                          ),
                          child:
                          ZegoSendCallInvitationButton(
                            invitees: [
                              ZegoUIKitUser(
                                id: ZegoCallService.sanitizeUserId(widget.chat.id),
                                name: widget.chat.name,
                              ),
                            ],
                            isVideoCall: true,
                            resourceID: ZegoCallService.resourceID,
                            buttonSize: const Size(44, 44),
                            borderRadius: 22,
                            icon: ButtonIcon(
                              icon: Icon(
                                Icons.videocam_rounded,
                                color: AppColors.primaryDeep,
                                size: 22,
                              ),
                            ),
                            // Omba camera + microphonе kabla ya kutuma invitation.
                            onWillPressed: () =>
                                _ensureCallPermissions(isVideo: true),
                            onPressed: (code, message, _) {
                              if (code != '0' && mounted) {
                                showAppNotification(
                                  context,
                                  'Call failed: $message',
                                  type: AppNotificationType.error,
                                );
                              }
                            },
                          ),
                        ),

                        // GIFT
                        Container(
                          margin:
                          const EdgeInsets.only(
                            right: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors
                                .coinGoldDark
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons
                                  .card_giftcard_rounded,
                              color: AppColors
                                  .coinGoldDark,
                              size: 24,
                            ),
                            onPressed: () {
                              GiftModalBottomSheet.show(
                                context,
                                recipientUid:
                                widget.chat.id,
                                recipientName:
                                widget.chat.name,
                                onGiftSent:
                                    (selectedGift) {
                                  if (!mounted) return;

                                  // Send gift as a chat message so it appears in the conversation
                                  _sendMessage(
                                    type: 'gift',
                                    text: '${selectedGift.emoji ?? '🎁'} ${selectedGift.name}',
                                    mediaUrl: selectedGift.imageUrl,
                                  );

                                  _showMessage(
                                    _lang.t(
                                      'You sent ${selectedGift.emoji ?? '🎁'} ${selectedGift.name} to ${widget.chat.name}!',
                                      sw: 'You sent to ${selectedGift.emoji ?? '🎁'} ${selectedGift.name} to ${widget.chat.name}!',
                                    ),
                                    backgroundColor:
                                    Colors.green,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              body: Stack(
                children: [
                  // ==================================================
                  // DECORATIVE BACKGROUND
                  // ==================================================

                  Positioned(
                    top: -50,
                    right: -50,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor
                            .withValues(alpha: 0.15),
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 100,
                    left: -60,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.pinkAccent
                            .withValues(alpha: 0.1),
                      ),
                    ),
                  ),

                  // ==================================================
                  // CHAT
                  // ==================================================

                  Column(
                    children: [
                      // ---- BACKGROUND-REFRESH MESSAGE LIST ----
                      // Uses the CACHED _messagesStream, so presence/typing/
                      // keystroke setStates reuse the same subscription and
                      // ONLY this Expanded rebuilds.
                      Expanded(
                        child: StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _messagesStream,
                          builder:
                              (context, snapshot) {
                            if (snapshot
                                .connectionState ==
                                ConnectionState
                                    .waiting &&
                                !snapshot.hasData) {
                              return const Center(
                                child:
                                HeartLoader(size: 60),
                              );
                            }

                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  "Failed to load messages.",
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }

                            if (!snapshot.hasData ||
                                snapshot.data!.isEmpty) {
                              return Center(
                                child: Text(
                                  "Anzisha mazungumzo leo!",
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }

                            final messages = snapshot.data!;

                            // Post-frame only: queue seen-receipts + scroll +
                            // count WITHOUT mutating state during build, so
                            // these side-effects can't loop a page refresh.
                            if (!_chatLocked) {
                              for (int i = 0;
                                  i < messages.length && i < 30;
                                  i++) {
                                _markAsSeen(
                                    messages[i], messages, chatId);
                              }
                            }
                            if (!_seenFrameScheduled) {
                              _seenFrameScheduled = true;
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                _seenFrameScheduled = false;
                                if (!mounted) return;
                                if (messages.length >
                                    _renderedMessageCount) {
                                  _scrollToBottom();
                                }
                                _renderedMessageCount =
                                    messages.length;
                              });
                            }

                            return ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              physics:
                              const BouncingScrollPhysics(),
                              padding:
                              const EdgeInsets.only(
                                top: 100,
                                left: 16,
                                right: 16,
                                bottom: 16,
                              ),
                              itemCount:
                              messages.length,
                              itemBuilder:
                                  (context, index) {
                                final rawData = messages[index];

                                final bubble =
                                _buildMessageBubble(
                                  rawData,
                                  accentColor,
                                  isLuxury,
                                  chatId,
                                );

                                // Animate only genuinely NEW
                                // messages (index 0 of the
                                // reversed list) so scrolling
                                // stays smooth. _renderedMessageCount is
                                // updated post-frame above — never here —
                                // so this builder stays side-effect free.
                                final canAnimate =
                                    index == 0 &&
                                        messages.length >
                                            _renderedMessageCount;

                                if (!canAnimate) {
                                  return bubble;
                                }

                                return _MessageEntrance(
                                  key: ValueKey(
                                    messages[index]['id'],
                                  ),
                                  child: bubble,
                                );
                              },
                            );
                          },
                        ),
                      ),

                      // TYPING INDICATOR: cached stream so keystrokes/presence
                      // rebuild ONLY this row, never the message list/page.
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _typingRoomStream,
                        builder: (context, typingSnapshot) {
                          bool peerTyping = false;

                          if (typingSnapshot.hasData && typingSnapshot.data!.isNotEmpty) {
                            final data = typingSnapshot.data!.first;
                            // Column 'typing' ina uid wa mwenye kuandika to sasa.
                            peerTyping = data['typing'] == widget.chat.id;
                          }

                          return AnimatedSwitcher(
                            duration: const Duration(
                              milliseconds: 250,
                            ),
                            transitionBuilder:
                                (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(
                                      0,
                                      0.4,
                                    ),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: peerTyping
                                ? Align(
                              key: const ValueKey(
                                'typing',
                              ),
                              alignment: Alignment
                                  .centerLeft,
                              child: Padding(
                                padding:
                                const EdgeInsets
                                    .only(
                                  left: 16,
                                  bottom: 6,
                                ),
                                child:
                                _TypingIndicator(
                                  isLuxury:
                                  isLuxury,
                                  accentColor:
                                  accentColor,
                                ),
                              ),
                            )
                                : const SizedBox.shrink(
                              key: ValueKey(
                                'idle',
                              ),
                            ),
                          );
                        },
                      ),

                      // ==================================================
                      // INPUT BAR
                      // ==================================================

                      Padding(
                        padding:
                        const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius:
                          AppRadius.xl,
                          child: BackdropFilter(
                            filter:
                            ImageFilter.blur(
                              sigmaX: 15,
                              sigmaY: 15,
                            ),
                            child: Container(
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration:
                              BoxDecoration(
                                // FIXED: frosted white pill for everyone.
                                color: Colors.white
                                    .withValues(alpha: 0.8),
                                borderRadius:
                                AppRadius.pill,
                                border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.6),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.05),
                                    blurRadius: 20,
                                    offset:
                                    const Offset(
                                      0,
                                      10,
                                    ),
                                  ),
                                ],
                              ),
                              child: SafeArea(
                                top: false,
                                child: Row(
                                  children: [
                                    // MEDIA
                                    _isUploadingMedia.value
                                        ? const Padding(
                                      padding:
                                      EdgeInsets
                                          .all(
                                        12,
                                      ),
                                      child: SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: HeartLoader(
                                          size: 22,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    )
                                        : IconButton(
                                      icon: Icon(
                                        Icons
                                            .add_circle_rounded,
                                        color:
                                        accentColor,
                                        size: 30,
                                      ),
                                      onPressed:
                                      _showMediaPickerOptions,
                                    ),

                                    // MESSAGE / RECORDING
                                    Expanded(
                                      child: _isRecording
                                          ? AnimatedContainer(
                                        duration:
                                        const Duration(
                                          milliseconds:
                                          300,
                                        ),
                                        padding:
                                        const EdgeInsets
                                            .symmetric(
                                          horizontal:
                                          16,
                                          vertical:
                                          12,
                                        ),
                                        decoration:
                                        BoxDecoration(
                                          color: Colors
                                              .red
                                              .shade50,
                                          borderRadius:
                                          BorderRadius
                                              .circular(
                                            24,
                                          ),
                                        ),
                                        child:
                                        Row(
                                          children: [
                                            AnimatedBuilder(
                                              animation:
                                              _recordingPulse,
                                              builder: (context,
                                                  child) =>
                                                  Transform
                                                      .scale(
                                                    scale: 1.0 +
                                                        0.25 *
                                                            _recordingPulse
                                                                .value,
                                                    child:
                                                    child,
                                                  ),
                                              child:
                                              const Icon(
                                                Icons
                                                    .mic_rounded,
                                                color:
                                                AppColors.error,
                                                size:
                                                20,
                                              ),
                                            ),
                                            const SizedBox(
                                              width:
                                              8,
                                            ),
                                            const Text(
                                              "Recording Voice Note...",
                                              style:
                                              TextStyle(
                                                color:
                                                AppColors.error,
                                                fontWeight:
                                                FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                          : TextField(
                                        controller:
                                        _messageController,
                                        textInputAction:
                                        TextInputAction
                                            .send,
                                        onSubmitted:
                                            (_) {
                                          if (_messageController
                                              .text
                                              .trim()
                                              .isNotEmpty) {
                                            _sendMessage(
                                              type:
                                              'text',
                                            );
                                          }
                                        },
                                        style:
                                        const TextStyle(
                                          color: Colors
                                              .black87,
                                        ),
                                        decoration:
                                        const InputDecoration(
                                          hintText:
                                          "Type a message...",
                                          hintStyle:
                                          TextStyle(
                                            color: Colors
                                                .black38,
                                          ),
                                          border:
                                          InputBorder
                                              .none,
                                          contentPadding:
                                          EdgeInsets
                                              .symmetric(
                                            horizontal:
                                            12,
                                            vertical:
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(
                                      width: 6,
                                    ),

                                    // SEND / MIC / STOP
                                    GestureDetector(
                                      onTap:
                                      _isSendingMessage.value
                                          ? null
                                          : () {
                                        if (_isRecording) {
                                          _toggleVoiceRecording();
                                        } else if (_messageController
                                            .text
                                            .trim()
                                            .isNotEmpty) {
                                          _sendMessage(
                                            type:
                                            'text',
                                          );
                                        } else {
                                          _toggleVoiceRecording();
                                        }
                                      },
                                      child:
                                      AnimatedContainer(
                                        duration:
                                        const Duration(
                                          milliseconds:
                                          200,
                                        ),
                                        padding:
                                        const EdgeInsets
                                            .all(
                                          12,
                                        ),
                                        decoration:
                                        BoxDecoration(
                                          // FIXED GRADIENT: rose for send,
                                          // red only while recording.
                                          gradient:
                                          _isRecording
                                              ? const LinearGradient(
                                            colors: [
                                              Colors
                                                  .red,
                                              Colors
                                                  .redAccent,
                                            ],
                                          )
                                              : const LinearGradient(
                                            colors: AppColors
                                                .primaryGradient,
                                          ),
                                          shape:
                                          BoxShape
                                              .circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.4),
                                              blurRadius:
                                              10,
                                              offset:
                                              const Offset(
                                                0,
                                                4,
                                              ),
                                            ),
                                          ],
                                        ),
                                        child:
                                        ValueListenableBuilder<
                                            TextEditingValue>(
                                          valueListenable:
                                          _messageController,
                                          builder: (context,
                                              textValue, _) {
                                            final bool hasText =
                                                textValue.text
                                                    .trim()
                                                    .isNotEmpty;
                                            return AnimatedSwitcher(
                                              duration:
                                              const Duration(
                                                milliseconds:
                                                200,
                                              ),
                                              transitionBuilder:
                                                  (child,
                                                  animation) =>
                                                  ScaleTransition(
                                                    scale:
                                                    animation,
                                                    child:
                                                    child,
                                                  ),
                                              child: Icon(
                                                _isRecording
                                                    ? Icons
                                                    .stop_rounded
                                                    : (hasText
                                                    ? Icons
                                                    .send_rounded
                                                    : Icons
                                                    .mic_rounded),
                                                key: ValueKey(
                                                  _isRecording
                                                      ? 'stop'
                                                      : (hasText
                                                      ? 'send'
                                                      : 'mic'),
                                                ),
                                                color:
                                                Colors.white,
                                                size: 22,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ==================================================
                  // CHAT LOCK OVERLAY (coin gate) — IKO MWISHO to Stack
                  // ili iwe JUU ya kila kitu (pia juu ya input bar) ili
                  // mtumiaji ashindwe kuandika bila kulipa. Ukilipa, DB
                  // inahifadhi `unlocked_by` -> overlay inatoweka MILELE.
                  // ==================================================
                  if (_chatLocked)
                    Positioned.fill(
                      child: ClipRRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            color: Colors.white
                                .withValues(alpha: 0.78),
                            child: _buildChatLockOverlay(isLuxury, accentColor),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
  }

  // ============================================================
  // MESSAGE BUBBLE
  // ============================================================

  Widget _buildMessageBubble(
      Map<String, dynamic> msg,
      Color accentColor,
      bool isLuxury,
      String chatId,
      ) {
    final user = currentUser;

    if (user == null) {
      return const SizedBox.shrink();
    }

    final bool isMe =
        msg['sender_id'] == user.id;

    final String type =
        msg['type']?.toString() ?? 'text';

    final String text =
        msg['content']?.toString() ?? '';

    final String mediaUrl =
        msg['media_url']?.toString() ?? '';

    return Align(
      alignment: isMe
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin:
        const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(
          maxWidth:
          MediaQuery.of(context).size.width *
              0.75,
        ),
        decoration: BoxDecoration(
          // FIXED GRADIENT: single rose gradient for MY bubbles
          // (AppColors.primaryGradient #FF4B6E -> #E03355), solid white
          // for peer bubbles. No per-user tinting.
          gradient: isMe
              ? const LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isMe ? null : Colors.white,
          borderRadius:
          BorderRadius.only(
            topLeft:
            const Radius.circular(22),
            topRight:
            const Radius.circular(22),
            bottomLeft: isMe
                ? const Radius.circular(22)
                : const Radius.circular(4),
            bottomRight: isMe
                ? const Radius.circular(4)
                : const Radius.circular(22),
          ),
          boxShadow: [
            BoxShadow(
              color: isMe
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius:
          BorderRadius.only(
            topLeft:
            const Radius.circular(22),
            topRight:
            const Radius.circular(22),
            bottomLeft: isMe
                ? const Radius.circular(22)
                : const Radius.circular(4),
            bottomRight: isMe
                ? const Radius.circular(4)
                : const Radius.circular(22),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 5,
              sigmaY: 5,
            ),
            child: Padding(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // TEXT
                  // ==================================================

                  if (type == 'text')
                    Text(
                      text,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight:
                        FontWeight.w500,
                      ),
                    ),

                  // ==================================================
                  // IMAGE
                  // ==================================================

                  if (type == 'image')
                    _buildChatImage(
                      mediaUrl,
                      isMe,
                      isLuxury,
                    ),

                  // ==================================================
                  // VOICE NOTE (audio) — play/pause + progress + duration.
                  // URL ni ya Supabase Storage (chat_media) kwenye
                  // messages.media_url; mpokeaji anacheza moja kwa moja.
                  // ==================================================

                  if (type == 'audio' && mediaUrl.isNotEmpty)
                    SizedBox(
                      width: 220,
                      child: VoiceNoteBubble(
                        mediaUrl: mediaUrl,
                        isMe: isMe,
                        isLuxury: isLuxury,
                      ),
                    ),

                  // GIFT — fixed gold card for everyone.
                  if (type == 'gift')
                    _buildGiftMessage(
                      text,
                      mediaUrl,
                      isMe,
                      isLuxury,
                      accentColor,
                    ),

                  // ==================================================
                  // TIMESTAMP + READ RECEIPT
                  // ==================================================

                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(msg['created_at']),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg['seen'] == true
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 14,
                          color: msg['seen'] == true
                              ? const Color(0xFF4FC3F7) // Light blue — WhatsApp-style "seen"
                              : Colors.white.withValues(alpha: 0.6),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final DateTime date;
      if (timestamp is DateTime) {
        date = timestamp;
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        date = (timestamp as dynamic).toDate();
      }
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Widget _buildGiftMessage(
      String giftText,
      String? mediaUrl,
      bool isMe,
      bool isLuxury,
      Color accentColor,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.coinGold.withValues(alpha: 0.2),
            AppColors.coinGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.md,
        border: Border.all(
          color: AppColors.coinGold.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.coinGold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: mediaUrl != null && mediaUrl.isNotEmpty
                ? Image.network(
              mediaUrl,
              width: 30,
              height: 30,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.coinGoldDark,
                size: 24,
              ),
            )
                : const Icon(
              Icons.card_giftcard_rounded,
              color: AppColors.coinGoldDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lang.t('Gift Sent!', sw: 'Gift Sent!'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  giftText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHAT IMAGE
  // ============================================================

  Widget _buildChatImage(
      String mediaUrl,
      bool isMe,
      bool isLuxury,
      ) {
    if (mediaUrl.trim().isEmpty) {
      return _brokenMediaPlaceholder(
        icon: Icons.broken_image_rounded,
        isMe: isMe,
        isLuxury: isLuxury,
      );
    }

    final url = mediaUrl.trim();

    if (_isValidUrl(url)) {
      return GestureDetector(
        onTap: () => _openImagePreview(url),
        child: ClipRRect(
          borderRadius:
          AppRadius.md,
          child: Image.network(
            url,
            height: 190,
            width: 240,
            fit: BoxFit.cover,
          errorBuilder:
              (context, error, stackTrace) {
            return _brokenMediaPlaceholder(
              icon:
              Icons.broken_image_rounded,
              isMe: isMe,
              isLuxury: isLuxury,
            );
          },
          loadingBuilder:
              (context, child, progress) {
            if (progress == null) {
              return child;
            }

            return Container(
              height: 190,
              width: 240,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white
                    .withValues(alpha: 0.15)
                    : Colors.black
                    .withValues(alpha: 0.05),
                borderRadius:
                AppRadius.md,
              ),
              child:
              const HeartLoader(size: 42),
            );
          },
          ),
        ),
      );
    }

    final file = File(url);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return GestureDetector(
            onTap: () => _openImagePreview(url),
            child: ClipRRect(
            borderRadius:
            AppRadius.md,
            child: Image.file(
              file,
              height: 190,
              width: 240,
              fit: BoxFit.cover,
              errorBuilder:
                  (context, error, stackTrace) {
                return _brokenMediaPlaceholder(
                  icon:
                  Icons.broken_image_rounded,
                  isMe: isMe,
                  isLuxury: isLuxury,
                );
              },
            ),
          ),
          );
        }

        return _brokenMediaPlaceholder(
          icon: Icons.broken_image_rounded,
          isMe: isMe,
          isLuxury: isLuxury,
        );
      },
    );
  }

  // ============================================================
  // IMAGE PREVIEW + DOWNLOAD
  // ============================================================

  /// Hufungua picha iliyotumwa kwenye preview kubwa (fullscreen)
  /// yenye uwezo wa ku-zoom na kitufe cha kudownload.
  void _openImagePreview(String mediaUrl) {
    final url = mediaUrl.trim();
    if (url.isEmpty || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ChatImagePreviewPage(imageUrl: url),
      ),
    );
  }

  // ============================================================
  // BROKEN MEDIA
  // ============================================================

  Widget _brokenMediaPlaceholder({
    required IconData icon,
    required bool isMe,
    required bool isLuxury,
  }) {
    // FIXED: same muted placeholder for every bubble.
    return Container(
      width: 220,
      height: 130,
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius:
        AppRadius.md,
      ),
      child: Column(
        mainAxisAlignment:
        MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 38,
            color: isMe
                ? Colors.white70
                : Colors.black38,
          ),
          const SizedBox(height: 8),
          Text(
            "Media haipatikani",
            style: TextStyle(
              color: isMe
                  ? Colors.white70
                  : Colors.black45,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Skrini ya fullscreen ya ku-preview picha ya chat.
class _ChatImagePreviewPage extends StatefulWidget {
  final String imageUrl;

  const _ChatImagePreviewPage({required this.imageUrl});

  @override
  State<_ChatImagePreviewPage> createState() =>
      _ChatImagePreviewPageState();
}

class _ChatImagePreviewPageState
    extends State<_ChatImagePreviewPage> {
  bool _downloading = false;

  bool get _isRemote =>
      widget.imageUrl.startsWith('http://') ||
      widget.imageUrl.startsWith('https://');

  Future<void> _downloadImage() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      Uint8List bytes;
      if (_isRemote) {
        final client = HttpClient();
        try {
          final request =
              await client.getUrl(Uri.parse(widget.imageUrl));
          final response = await request.close();
          if (response.statusCode != 200) {
            throw Exception('Download ${response.statusCode}');
          }
          final chunks = <int>[];
          await for (final chunk in response) {
            chunks.addAll(chunk);
          }
          bytes = Uint8List.fromList(chunks);
        } finally {
          client.close();
        }
      } else {
        final file = File(widget.imageUrl);
        if (!await file.exists()) {
          throw Exception('File not found');
        }
        bytes = await file.readAsBytes();
      }

      if (bytes.isEmpty) throw Exception('Empty file');

      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final name =
          'pacific_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final saved = File('${dir.path}/$name');
      await saved.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      showAppNotification(
        context,
        'Picha imehifadhiwa',
        color: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      showAppNotification(
        context,
        'Download imeshindikana. Jaribu tena.',
        color: Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Picha',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          _downloading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Download',
                  icon: const Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _downloadImage,
                ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: _isRemote
              ? Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                )
              : Image.file(
                  File(widget.imageUrl),
                  fit: BoxFit.contain,
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _downloading ? null : _downloadImage,
              icon: _downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(
                _downloading ? 'Inapakua...' : 'Download',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MESSAGE ENTRANCE ANIMATION (new messages slide + fade in)
// ============================================================

class _MessageEntrance extends StatefulWidget {
  final Widget child;

  const _MessageEntrance({super.key, required this.child});

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

// ============================================================
// TYPING INDICATOR â€” three bouncing dots inside a bubble
// ============================================================

class _TypingIndicator extends StatefulWidget {
  final bool isLuxury;
  final Color accentColor;

  const _TypingIndicator({
    required this.isLuxury,
    required this.accentColor,
  });

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIXED palette: white card + rose dots for everyone.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t =
              ((_controller.value - i * 0.18) % 1.0).abs();
              final bounce = 1.0 - (1 - t).abs() * 0.9;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.translate(
                  offset: Offset(0, -5 * bounce),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary
                          .withValues(alpha: 0.35 + 0.65 * bounce),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}