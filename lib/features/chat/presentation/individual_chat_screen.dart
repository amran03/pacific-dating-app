import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:pacific_dating_app/features/profile/presentation/public_profile_screen.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';
import 'package:pacific_dating_app/features/chat/presentation/widgets/gift_modal_bottom_sheet.dart';
import 'package:pacific_dating_app/core/services/presence_service.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/localization/app_language.dart';

import 'call_screen.dart';

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

  User? get currentUser => FirebaseAuth.instance.currentUser;

  AppLanguage get _lang => AppLanguage.instance;

  String? _chatId;

  bool _isRecording = false;

  // ValueNotifier badala ya setState — inapunguza rebuilds za ukurasa mzima
  // (WhatsApp-style smooth typing).
  final ValueNotifier<bool> _isUploadingMedia = ValueNotifier(false);
  final ValueNotifier<bool> _isSendingMessage = ValueNotifier(false);

  String? _currentlyPlayingPath;
  bool _isPlaying = false;

  // Chat lock state — track whether chat is unlocked for this session.
  bool _chatUnlocked = false;

  StreamSubscription<void>? _playerCompleteSubscription;

  // ---- Typing indicator (Firestore-backed, throttled writes) ----
  DocumentReference<Map<String, dynamic>>? _chatRoomRef;
  Timer? _typingClearTimer;
  DateTime? _lastTypingWrite;

  // ---- Smooth chat: entrance animation bookkeeping ----
  int _lastMessageCount = 0;

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
      final ids = [user.uid, widget.chat.id]..sort();
      _chatId = ids.join('_');
      _chatRoomRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_chatId);
    }

    _messageController.addListener(_onMessageChanged);

    // Mark all unread messages from the peer as seen when opening the chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMessagesAsSeen();
      _checkChatLockStatus();
    });

    _playerCompleteSubscription =
        _audioPlayer.onPlayerComplete.listen((_) {
          if (!mounted) return;

          setState(() {
            _isPlaying = false;
            _currentlyPlayingPath = null;
          });
        });
  }

  /// Checks if the chat is locked and sets _chatUnlocked accordingly
  Future<void> _checkChatLockStatus() async {
    final user = currentUser;
    if (user == null || _chatId == null) return;

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_chatId)
          .get();

      bool isUnlocked = false;
      if (chatDoc.exists) {
        final unlockedBy = chatDoc.data()?['unlockedBy'] as List<dynamic>?;
        isUnlocked = unlockedBy?.contains(user.uid) ?? false;
      }

      // If already unlocked, no need to check further
      if (isUnlocked) {
        _chatUnlocked = true;
        return;
      }

      // Check the unlock price from the other user's profile
      final otherUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.chat.id)
          .get();
      
      final price = (otherUserDoc.data()?['chatUnlockPrice'] ?? 0) as int;
      
      // Chat is free (price 0) or already unlocked
      if (price <= 0) {
        _chatUnlocked = true;
      }
      // Otherwise, chat remains locked
    } catch (e) {
      debugPrint('Error checking chat lock status: $e');
    }
  }

  /// Unlocks the chat by paying the required coins
  Future<void> _unlockChat() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final matchmakingService = MatchmakingService();
      await matchmakingService.payAndUnlockChat(widget.chat.id);
      
      if (mounted) {
        setState(() {
          _chatUnlocked = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lang.t('Chat Unlocked! 🎉', sw: 'Mazungumzo Yamefunguliwa! 🎉')),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String message = _lang.t('Failed to unlock chat', sw: 'Imeshindikana kufungua mazungumzo');
        if (e.toString().contains('INSUFFICIENT_COINS')) {
          message = _lang.t('Not enough Pacific Coins', sw: 'Huna Pasific Coins za kutosha');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
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
    final ref = _chatRoomRef;
    final uid = currentUser?.uid;
    if (ref == null || uid == null) return;

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
      ref
          .set(
        {
          'typing_$uid': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      )
          .catchError((_) {});
    }

    _typingClearTimer?.cancel();
    _typingClearTimer = Timer(const Duration(seconds: 3), () {
      _lastTypingWrite = null;
      _clearTypingStatus(uid);
    });
  }

  void _clearTypingStatus(String uid) {
    _chatRoomRef
        ?.set(
      {
        'typing_$uid': FieldValue.delete(),
      },
      SetOptions(merge: true),
    )
        .catchError((_) {});
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();

    _typingClearTimer?.cancel();
    _recordingPulse.dispose();

    // Best-effort: clear our typing flag when leaving the chat.
    final uid = currentUser?.uid;
    if (uid != null) {
      _clearTypingStatus(uid);
    }

    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();

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

  void _showMessage(
      String message, {
        Color? backgroundColor,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  bool _isValidUrl(String? url) {
    if (url == null) return false;

    final value = url.trim();

    return value.isNotEmpty &&
        (value.startsWith('http://') ||
            value.startsWith('https://'));
  }

  String _safeTier(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.toLowerCase().trim();
    }

    return 'none';
  }

  // ============================================================
  // VOICE RECORDING
  // ============================================================

  // ============================================================
  // READ RECEIPTS
  // ============================================================

  /// Marks all unread messages sent by the other person as "seen"
  /// when this chat screen is open (WhatsApp-style read receipts).
  Future<void> _markMessagesAsSeen() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final unreadSnap = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_chatId)
          .collection('messages')
          .where('receiverId', isEqualTo: user.uid)
          .where('seen', isEqualTo: false)
          .get();

      if (unreadSnap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadSnap.docs) {
        batch.update(doc.reference, {
          'seen': true,
          'seenAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {
      // Silently fail — read receipts are best-effort
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
          "Tafadhali ruhusu microphone kurekodi sauti.",
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
        "Imeshindikana kuanzisha kurekodi sauti.",
      );
    }
  }

  // ============================================================
  // AUDIO PLAYER
  // ============================================================

  Future<void> _playAudio(String? path) async {
    if (path == null || path.trim().isEmpty) {
      _showMessage("Voice note haipatikani.");
      return;
    }

    final audioPath = path.trim();

    try {
      if (_isPlaying &&
          _currentlyPlayingPath == audioPath) {
        await _audioPlayer.pause();

        if (!mounted) return;

        setState(() {
          _isPlaying = false;
        });

        return;
      }

      await _audioPlayer.stop();

      if (audioPath.startsWith('http://') ||
          audioPath.startsWith('https://')) {
        await _audioPlayer.play(
          UrlSource(audioPath),
        );
      } else {
        final file = File(audioPath);

        if (!await file.exists()) {
          _showMessage("Voice note haipatikani kwenye kifaa.");
          return;
        }

        await _audioPlayer.play(
          DeviceFileSource(audioPath),
        );
      }

      if (!mounted) return;

      setState(() {
        _isPlaying = true;
        _currentlyPlayingPath = audioPath;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isPlaying = false;
        _currentlyPlayingPath = null;
      });

      _showMessage(
        "Imeshindikana kucheza voice note.",
      );
    }
  }

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
        "Imeshindikana kuchagua picha.",
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
        "Akaunti yako haijapatikana. Tafadhali ingia tena.",
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

        final storageRef = FirebaseStorage.instance
            .ref()
            .child('chat_media')
            .child(chatId)
            .child(
          '${DateTime.now().millisecondsSinceEpoch}.$extension',
        );

        await storageRef.putFile(file);

        finalMediaUrl =
        await storageRef.getDownloadURL();
      } catch (e) {
        if (!mounted) return;

        _isUploadingMedia.value = false;

        _showMessage(
          "Imeshindikana kupakia faili.",
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
        'senderId': user.uid,
        'receiverId': widget.chat.id,
        'type': type,
        'text': messageText,
        'mediaUrl': finalMediaUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false,
      };

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatId)
          .collection('messages')
          .add(messageData);

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
        user.uid,
        widget.chat.id,
      ]..sort();

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatId)
          .set(
        {
          'participants': participantIds,
          'lastMessage': previewText,
          'lastMessageAt':
          FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        "Imeshindikana kutuma ujumbe. Jaribu tena.",
      );
    } finally {
      if (mounted) {
        _isSendingMessage.value = false;
        _isUploadingMedia.value = false;
      }
    }
  }

  // ============================================================
  // READ RECEIPT — messages from the peer are marked as seen
  // the moment they appear on screen (only if not already
  // marked). Batches writes via Firestore writeBatch.
  // ============================================================

  /// Pending seen updates collected during a single build cycle;
  /// flushed once per frame to avoid hammering Firestore.
  final List<String> _pendingSeenIds = [];

  void _markAsSeen(
    Map<String, dynamic> rawData,
    List<QueryDocumentSnapshot> messages,
    String chatId,
  ) {
    final user = currentUser;
    if (user == null) return;

    // Only mark peer's messages (not my own).
    if (rawData['senderId'] == user.uid) return;

    // Already seen — skip.
    if (rawData['seen'] == true) return;

    // Find this message's doc id by matching rawData reference.
    String? docId;
    for (final m in messages) {
      if (m.data() == rawData) {
        docId = m.id;
        break;
      }
    }
    if (docId == null || _pendingSeenIds.contains(docId)) return;

    _pendingSeenIds.add(docId);

    // Flush on next microtask (deduplicates burst builds).
    if (_pendingSeenIds.length == 1) {
      Future.microtask(_flushSeenUpdates);
    }
  }

  void _flushSeenUpdates() {
    if (_pendingSeenIds.isEmpty || !mounted) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final id in _pendingSeenIds) {
      final ref = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(_chatId)
          .collection('messages')
          .doc(id);
      batch.update(ref, {'seen': true});
    }
    _pendingSeenIds.clear();

    batch.commit().catchError((_) {
      // Silently ignore — read receipt is best-effort.
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
                color: Colors.white.withOpacity(0.92),
                borderRadius:
                const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
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
                  color: Colors.black.withOpacity(0.12),
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
  // VIP THEME
  // ============================================================

  Color _getThemeBackgroundColor(String tier) {
    switch (tier) {
      case 'diamond':
        return const Color(0xFF1A0B2E);

      case 'gold':
        return const Color(0xFF2C2416);

      case 'bronze':
        return const Color(0xFF24170F);

      default:
        return const Color(0xFFF3F4F8);
    }
  }

  Color _getThemeAccentColor(String tier) {
    switch (tier) {
      case 'diamond':
        return const Color(0xFFB9F2FF);

      case 'gold':
        return const Color(0xFFFFD700);

      case 'bronze':
        return const Color(0xFFCD7F32);

      default:
        return AppColors.primary;
    }
  }

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
            color: accentColor.withOpacity(0.25),
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
    return Container(
      width: radius * 2,
      height: radius * 2,
      color: isLuxury
          ? Colors.white.withOpacity(0.12)
          : Colors.grey.shade200,
      child: Icon(
        Icons.person_rounded,
        size: radius * 1.15,
        color: isLuxury
            ? Colors.white54
            : Colors.grey.shade500,
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
            "Mtumiaji hajapatikana.\nTafadhali ingia tena.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.chat.id)
          .snapshots(),
      builder: (context, snapshot) {
        String otherTier = 'none';

        if (snapshot.hasData &&
            snapshot.data!.exists) {
          final data =
          snapshot.data!.data();

          if (data is Map<String, dynamic>) {
            otherTier =
                _safeTier(data['badgeTier']);
          }
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, mySnapshot) {
            String myTier = 'none';

            if (mySnapshot.hasData &&
                mySnapshot.data!.exists) {
              final data =
              mySnapshot.data!.data();

              if (data is Map<String, dynamic>) {
                myTier =
                    _safeTier(data['badgeTier']);
              }
            }

            String activeTier = 'none';

            if (otherTier == 'diamond' ||
                myTier == 'diamond') {
              activeTier = 'diamond';
            } else if (otherTier == 'gold' ||
                myTier == 'gold') {
              activeTier = 'gold';
            } else if (otherTier == 'bronze' ||
                myTier == 'bronze') {
              activeTier = 'bronze';
            }

            final bgColor =
            _getThemeBackgroundColor(
              activeTier,
            );

            final accentColor =
            _getThemeAccentColor(
              activeTier,
            );

            final isLuxury =
                activeTier != 'none';

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
                      backgroundColor: isLuxury
                          ? bgColor.withOpacity(0.7)
                          : Colors.white
                          .withOpacity(0.7),
                      elevation: 0,
                      scrolledUnderElevation: 0,

                      leading: IconButton(
                        icon: Icon(
                          Icons
                              .arrow_back_ios_new_rounded,
                          color: isLuxury
                              ? Colors.white
                              : Colors.black87,
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
                                      color: isLuxury
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 16,
                                      fontWeight:
                                      FontWeight.bold,
                                    ),
                                  ),

                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration:
                                        BoxDecoration(
                                          color:
                                          AppColors
                                              .success,
                                          shape:
                                          BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors
                                                  .success
                                                  .withOpacity(
                                                0.5,
                                              ),
                                              blurRadius:
                                              6,
                                              spreadRadius:
                                              1.5,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 5,
                                      ),
                                      // REAL-TIME ONLINE STATUS (mfano
                                      // WhatsApp): inaonekana "Online" ikiwa
                                      // peer ifanye presence; bila isogwa,
                                      // inaonekana lastSeen.
                                      StreamBuilder<
                                          Map<String, dynamic>?>(
                                        stream: PresenceService
                                            .streamPeerPresence(
                                          widget.chat.id,
                                        ),
                                        builder: (context,
                                            presenceData) {
                                          final online =
                                              PresenceService
                                                  .isOnline(
                                                presenceData
                                                    .data,
                                              );
                                          final lastSeen =
                                              (presenceData
                                                  .data?['lastSeen']
                                                  as Timestamp?)
                                              ?.toDate();

                                          return Text(
                                            online
                                                ? (_lang.isSwahili
                                                ? 'Mofunga'
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
                                                  ? (isLuxury
                                                  ? Colors.white70
                                                  : Colors.black54)
                                                  : (isLuxury
                                                  ? Colors.white38
                                                  : Colors.black38),
                                              fontSize: 11,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      actions: [
                        // AUDIO CALL
                        Container(
                          margin:
                          const EdgeInsets.only(
                            right: 2,
                          ),
                          decoration:
                          BoxDecoration(
                            color: (isLuxury
                                ? accentColor
                                : AppColors
                                .primaryDeep)
                                .withOpacity(
                              0.12,
                            ),
                            shape:
                            BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip:
                            'Audio call',
                            icon: Icon(
                              Icons
                                  .call_rounded,
                              color: isLuxury
                                  ? accentColor
                                  : AppColors
                                  .primaryDeep,
                              size: 21,
                            ),
                            onPressed:
                                () {
                              CallScreen
                                  .push(
                                context,
                                callType:
                                CallType
                                    .audio,
                                peerName:
                                widget
                                    .chat
                                    .name,
                                peerAvatarUrl:
                                widget
                                    .chat
                                    .avatarUrl,
                                isOutgoing:
                                true,
                              );
                            },
                          ),
                        ),

                        // VIDEO CALL
                        Container(
                          margin:
                          const EdgeInsets.only(
                            right: 2,
                          ),
                          decoration:
                          BoxDecoration(
                            color: (isLuxury
                                ? accentColor
                                : AppColors
                                .primaryDeep)
                                .withOpacity(
                              0.12,
                            ),
                            shape:
                            BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip:
                            'Video call',
                            icon: Icon(
                              Icons
                                  .videocam_rounded,
                              color: isLuxury
                                  ? accentColor
                                  : AppColors
                                  .primaryDeep,
                              size: 22,
                            ),
                            onPressed:
                                () {
                              CallScreen
                                  .push(
                                context,
                                callType:
                                CallType
                                    .video,
                                peerName:
                                widget
                                    .chat
                                    .name,
                                peerAvatarUrl:
                                widget
                                    .chat
                                    .avatarUrl,
                                isOutgoing:
                                true,
                              );
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
                            color: (isLuxury
                                ? AppColors
                                .coinGold
                                : AppColors
                                .coinGoldDark)
                                .withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons
                                  .card_giftcard_rounded,
                              color: isLuxury
                                  ? AppColors
                                  .coinGold
                                  : AppColors
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
                                    text: '${selectedGift.emoji} ${selectedGift.name}',
                                  );

                                  _showMessage(
                                    _lang.t(
                                      'You sent ${selectedGift.emoji} ${selectedGift.name} to ${widget.chat.name}!',
                                      sw: 'Umemtumia ${selectedGift.emoji} ${selectedGift.name} kwa ${widget.chat.name}!',
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
                            .withOpacity(0.15),
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
                            .withOpacity(0.1),
                      ),
                    ),
                  ),

                  // ==================================================
                  // CHAT
                  // ==================================================

                  Column(
                    children: [
                      Expanded(
                        child: StreamBuilder<
                            QuerySnapshot>(
                          stream: FirebaseFirestore
                              .instance
                              .collection(
                            'chat_rooms',
                          )
                              .doc(chatId)
                              .collection(
                            'messages',
                          )
                              .orderBy(
                            'timestamp',
                            descending: true,
                          )
                              .snapshots(),
                          builder:
                              (context, snapshot) {
                            if (snapshot
                                .connectionState ==
                                ConnectionState
                                    .waiting) {
                              return const Center(
                                child:
                                CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  "Imeshindikana kupakia ujumbe.",
                                  style: TextStyle(
                                    color: isLuxury
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              );
                            }

                            if (!snapshot.hasData ||
                                snapshot
                                    .data!
                                    .docs
                                    .isEmpty) {
                              return Center(
                                child: Text(
                                  "Anzisha mazungumzo leo! ðŸ‘‹",
                                  style: TextStyle(
                                    color: isLuxury
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              );
                            }

                            final messages =
                                snapshot.data!.docs;

                            return ListView.builder(
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
                                final rawData =
                                messages[index]
                                    .data();

                                if (rawData
                                is! Map<String,
                                    dynamic>) {
                                  return const SizedBox
                                      .shrink();
                                }

                                final bubble =
                                _buildMessageBubble(
                                  rawData,
                                  accentColor,
                                  isLuxury,
                                  chatId,
                                );

                                // Mark unread messages as seen when they
                                // appear on-screen (read receipt).
                                _markAsSeen(rawData, messages, chatId);

                                // Animate only genuinely NEW
                                // messages (index 0 of the
                                // reversed list) so scrolling
                                // stays smooth.
                                final canAnimate =
                                    index == 0 &&
                                        messages.length >
                                            _lastMessageCount;

                                if (messages.length !=
                                    _lastMessageCount) {
                                  _lastMessageCount =
                                      messages.length;
                                }

                                if (!canAnimate) {
                                  return bubble;
                                }

                                return _MessageEntrance(
                                  key: ValueKey(
                                    messages[index].id,
                                  ),
                                  child: bubble,
                                );
                              },
                            );
                          },
                        ),
                      ),

                      // ==================================================
                      // TYPING INDICATOR (Firestore-backed)
                      // ==================================================

                      StreamBuilder<DocumentSnapshot>(
                        stream: _chatRoomRef?.snapshots(),
                        builder: (context, typingSnapshot) {
                          bool peerTyping = false;

                          final data = typingSnapshot
                              .data
                              ?.data();

                          if (data is Map<String, dynamic>) {
                            final ts = data[
                            'typing_${widget.chat.id}'];

                            if (ts is Timestamp) {
                              peerTyping = DateTime
                                  .now()
                                  .difference(
                                ts.toDate(),
                              ).inSeconds < 6;
                            }
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
                          BorderRadius.circular(30),
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
                                color: isLuxury
                                    ? Colors.black
                                    .withOpacity(0.5)
                                    : Colors.white
                                    .withOpacity(0.8),
                                borderRadius:
                                BorderRadius.circular(
                                  30,
                                ),
                                border: Border.all(
                                  color: isLuxury
                                      ? accentColor
                                      .withOpacity(
                                    0.3,
                                  )
                                      : Colors.white
                                      .withOpacity(
                                    0.6,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withOpacity(
                                      0.05,
                                    ),
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
                                        width: 22,
                                        height: 22,
                                        child:
                                        CircularProgressIndicator(
                                          strokeWidth:
                                          2.5,
                                          color: AppColors
                                              .primary,
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
                                        TextStyle(
                                          color: isLuxury
                                              ? Colors
                                              .white
                                              : Colors
                                              .black87,
                                        ),
                                        decoration:
                                        InputDecoration(
                                          hintText:
                                          "Type a message...",
                                          hintStyle:
                                          TextStyle(
                                            color: isLuxury
                                                ? Colors
                                                .white38
                                                : Colors
                                                .black38,
                                          ),
                                          border:
                                          InputBorder
                                              .none,
                                          contentPadding:
                                          const EdgeInsets
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
                                              : LinearGradient(
                                            colors: [
                                              accentColor,
                                              accentColor
                                                  .withOpacity(
                                                0.8,
                                              ),
                                            ],
                                          ),
                                          shape:
                                          BoxShape
                                              .circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: accentColor
                                                  .withOpacity(
                                                0.4,
                                              ),
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
                ],
              ),
            );
          },
        );
      },
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
        msg['senderId'] == user.uid;

    final String type =
        msg['type']?.toString() ?? 'text';

    final String text =
        msg['text']?.toString() ?? '';

    final String mediaUrl =
        msg['mediaUrl']?.toString() ?? '';

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
          gradient: isMe
              ? LinearGradient(
            colors: [
              accentColor,
              accentColor.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isMe
              ? null
              : (isLuxury
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.9)),
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
                  ? accentColor.withOpacity(0.25)
                  : Colors.black.withOpacity(0.04),
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
                        color: isMe
                            ? Colors.white
                            : (isLuxury
                            ? Colors.white
                            : Colors.black87),
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
                  // GIFT
                  // ==================================================

                  if (type == 'gift')
                    _buildGiftMessage(
                      text,
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
                        _formatTimestamp(msg['timestamp']),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? Colors.white.withOpacity(0.7)
                              : (isLuxury
                                  ? Colors.white38
                                  : Colors.black38),
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
                              : Colors.white.withOpacity(0.6),
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
      final date = timestamp is DateTime
          ? timestamp
          : (timestamp as dynamic).toDate();
      final hour = (date as DateTime).hour.toString().padLeft(2, '0');
      final minute = (date as DateTime).minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Widget _buildGiftMessage(
    String giftText,
    bool isMe,
    bool isLuxury,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.coinGold.withOpacity(0.2),
            AppColors.coinGold.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.coinGold.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.coinGold.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
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
                  _lang.t('Gift Sent!', sw: 'Zawadi Imetumwa!'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isLuxury ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  giftText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLuxury ? Colors.white70 : Colors.black54,
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
      return ClipRRect(
        borderRadius:
        BorderRadius.circular(16),
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
                    .withOpacity(0.15)
                    : Colors.black
                    .withOpacity(0.05),
                borderRadius:
                BorderRadius.circular(16),
              ),
              child:
              const CircularProgressIndicator(
                strokeWidth: 2,
              ),
            );
          },
        ),
      );
    }

    final file = File(url);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return ClipRRect(
            borderRadius:
            BorderRadius.circular(16),
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
  // AUDIO MESSAGE
  // ============================================================

  Widget _buildAudioMessage(
      String mediaUrl,
      String text,
      bool isMe,
      bool isLuxury,
      Color accentColor,
      ) {
    final bool currentlyPlaying =
        _isPlaying &&
            _currentlyPlayingPath ==
                mediaUrl;

    return GestureDetector(
      onTap: mediaUrl.trim().isEmpty
          ? null
          : () => _playAudio(mediaUrl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
            const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withOpacity(0.2)
                  : accentColor
                  .withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              currentlyPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: isMe
                  ? Colors.white
                  : accentColor,
              size: 26,
            ),
          ),

          const SizedBox(width: 10),

          Flexible(
            child: Text(
              text.isNotEmpty
                  ? text
                  : 'Voice Note',
              overflow:
              TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe
                    ? Colors.white
                    : (isLuxury
                    ? Colors.white
                    : Colors.black87),
                fontWeight:
                FontWeight.bold,
              ),
            ),
          ),
        ],
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
    return Container(
      width: 220,
      height: 130,
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.12)
            : (isLuxury
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.05)),
        borderRadius:
        BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment:
        MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 38,
            color: isMe
                ? Colors.white54
                : (isLuxury
                ? Colors.white54
                : Colors.black38),
          ),
          const SizedBox(height: 8),
          Text(
            "Media haipatikani",
            style: TextStyle(
              color: isMe
                  ? Colors.white54
                  : (isLuxury
                  ? Colors.white54
                  : Colors.black45),
              fontSize: 12,
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: widget.isLuxury
            ? Colors.black.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: widget.isLuxury
              ? widget.accentColor.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                      color: widget.isLuxury
                          ? widget.accentColor
                          .withOpacity(0.35 + 0.65 * bounce)
                          : AppColors.primary
                          .withOpacity(0.35 + 0.65 * bounce),
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
