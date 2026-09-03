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

import '../../../core/constants/app_color.dart';
import '../domain/models/chat_model.dart';
import '../../profile/presentation/public_profile_screen.dart';
import 'widgets/gift_modal_bottom_sheet.dart';

class IndividualChatScreen extends StatefulWidget {
  final ChatModel chat;

  const IndividualChatScreen({super.key, required this.chat});

  @override
  State<IndividualChatScreen> createState() => _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();

  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  final ImagePicker _picker = ImagePicker();
  final User? currentUser = FirebaseAuth.instance.currentUser;

  bool _isRecording = false;
  bool _isUploadingMedia = false;
  String? _currentlyPlayingPath;
  bool _isPlaying = false;

  // Kutengeneza chatRoomId ya kipekee kati ya watumiaji wawili
  late final String chatId;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    // Kuweka ID ya chumba cha mazungumzo kwa kuchanganya UID za watu wawili
    List<String> ids = [currentUser!.uid, widget.chat.id];
    ids.sort();
    chatId = ids.join('_');

    _messageController.addListener(() {
      setState(() {});
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _isPlaying = false;
        _currentlyPlayingPath = null;
      });
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- LOGIC YA KUREKODI SAUTI ---
  Future<void> _toggleVoiceRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        _sendMessage(type: 'audio', mediaUrl: path, text: '🎵 Voice Note');
      }
    } else {
      var status = await Permission.microphone.request();
      if (status.isGranted) {
        if (await _audioRecorder.hasPermission()) {
          final dir = await getApplicationDocumentsDirectory();
          final filePath =
              '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc),
            path: filePath,
          );

          setState(() {
            _isRecording = true;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Tafadhali ruhusu microphone kurekodi sauti.")),
          );
        }
      }
    }
  }

  // --- LOGIC YA KUCHEZA SAUTI ---
  Future<void> _playAudio(String path) async {
    if (_isPlaying && _currentlyPlayingPath == path) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
    } else {
      await _audioPlayer.stop();
      if (path.startsWith('http')) {
        await _audioPlayer.play(UrlSource(path));
      } else {
        await _audioPlayer.play(DeviceFileSource(path));
      }
      setState(() {
        _isPlaying = true;
        _currentlyPlayingPath = path;
      });
    }
  }

  // --- LOGIC YA KUCHUKUA PICHA ---
  Future<void> _pickImage(ImageSource source) async {
    final XFile? image =
    await _picker.pickImage(source: source, imageQuality: 70);
    if (image != null) {
      _sendMessage(type: 'image', mediaUrl: image.path);
    }
  }

  // --- KUTUMA UJUMBE KWENYE FIRESTORE ---
  void _sendMessage({required String type, String? text, String? mediaUrl}) async {
    if ((type == 'text' && _messageController.text.trim().isEmpty) &&
        mediaUrl == null) {
      return;
    }

    final messageText = text ?? _messageController.text.trim();
    _messageController.clear();

    String finalMediaUrl = mediaUrl ?? '';

    // Kama mediaUrl ni njia ya faili LOCAL (sio URL ya mtandaoni tayari),
    // ipandishe kwanza Firebase Storage. Bila hatua hii, mtu wa pili
    // (upande wa pili wa mazungumzo) asingeweza kuiona kabisa - njia ya
    // faili ya simu yako haipo kwenye simu yake.
    if (finalMediaUrl.isNotEmpty && !finalMediaUrl.startsWith('http')) {
      setState(() => _isUploadingMedia = true);
      try {
        final File file = File(finalMediaUrl);
        final String extension = type == 'audio' ? 'm4a' : 'jpg';
        final ref = FirebaseStorage.instance
            .ref()
            .child('chat_media')
            .child(chatId)
            .child('${DateTime.now().millisecondsSinceEpoch}.$extension');

        await ref.putFile(file);
        finalMediaUrl = await ref.getDownloadURL();
      } catch (e) {
        if (mounted) {
          setState(() => _isUploadingMedia = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Imeshindikana kupakia faili: $e")),
          );
        }
        return; // Usihifadhi ujumbe Firestore kama upload umeshindwa
      }
      if (mounted) setState(() => _isUploadingMedia = false);
    }

    final messageData = {
      'senderId': currentUser!.uid,
      'receiverId': widget.chat.id,
      'type': type,
      'text': messageText,
      'mediaUrl': finalMediaUrl,
      'timestamp': FieldValue.serverTimestamp(),
    };

    // Hifadhi kwenye Firestore chini ya chumba cha mazungumzo
    await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(chatId)
        .collection('messages')
        .add(messageData);

    // Sasisha 'preview' ya mazungumzo (jumbe ya mwisho + wakati) ili
    // ChatListScreen ionyeshe taarifa sahihi na ipange kwa hivi karibuni.
    String previewText;
    switch (type) {
      case 'image':
        previewText = '📷 Picha';
        break;
      case 'audio':
        previewText = '🎵 Ujumbe wa Sauti';
        break;
      default:
        previewText = messageText;
    }

    final List<String> ids = [currentUser!.uid, widget.chat.id]..sort();
    await FirebaseFirestore.instance.collection('chat_rooms').doc(chatId).set({
      'participants': ids,
      'lastMessage': previewText,
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _showMediaPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMediaOption(
                    icon: Icons.photo_library_rounded,
                    gradient: const LinearGradient(
                        colors: [Colors.purple, Colors.deepPurpleAccent]),
                    label: "Gallery",
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  _buildMediaOption(
                    icon: Icons.camera_alt_rounded,
                    gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.deepOrangeAccent]),
                    label: "Camera",
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ],
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
                  color: Colors.purple.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AppBar(
              backgroundColor: Colors.white.withOpacity(0.7),
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
              title: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PublicProfileScreen(uid: widget.chat.id),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundImage: NetworkImage(widget.chat.avatarUrl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.chat.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                "Online",
                                style: TextStyle(
                                    color: Colors.black54, fontSize: 11),
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
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.coinGold.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.card_giftcard_rounded,
                        color: AppColors.coinGold, size: 24),
                    onPressed: () {
                      GiftModalBottomSheet.show(
                        context,
                        recipientUid: widget.chat.id,
                        recipientName: widget.chat.name,
                        onGiftSent: (selectedGift) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  "Umemtumia ${selectedGift.emoji} ${selectedGift.name} ${widget.chat.name}!"),
                              backgroundColor: Colors.green,
                            ),
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
          // Background Aesthetic Decorative Orbs
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.15),
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
                color: Colors.pinkAccent.withOpacity(0.1),
              ),
            ),
          ),

          // Main Chat Body with StreamBuilder (Real-time Firestore)
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .doc(chatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "Anzisha mazungumzo leo! 👋",
                          style: TextStyle(color: Colors.black54),
                        ),
                      );
                    }

                    final messages = snapshot.data!.docs;

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.only(
                          top: 100, left: 16, right: 16, bottom: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msgData =
                        messages[index].data() as Map<String, dynamic>;
                        return _buildMessageBubble(msgData);
                      },
                    );
                  },
                ),
              ),

              // Bottom Input Bar na Glassmorphism Effect
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(30),
                        border:
                        Border.all(color: Colors.white.withOpacity(0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            _isUploadingMedia
                                ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                                : IconButton(
                              icon: const Icon(Icons.add_circle_rounded,
                                  color: AppColors.primary, size: 30),
                              onPressed: _showMediaPickerOptions,
                            ),
                            Expanded(
                              child: _isRecording
                                  ? AnimatedContainer(
                                duration:
                                const Duration(milliseconds: 300),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius:
                                  BorderRadius.circular(24),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.mic_rounded,
                                        color: Colors.red, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      "Recording Voice Note...",
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : TextField(
                                controller: _messageController,
                                style: const TextStyle(
                                    color: Colors.black87),
                                decoration: const InputDecoration(
                                  hintText: "Type a message...",
                                  hintStyle:
                                  TextStyle(color: Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                if (_messageController.text.trim().isNotEmpty) {
                                  _sendMessage(type: 'text');
                                } else {
                                  _toggleVoiceRecording();
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: _isRecording
                                      ? const LinearGradient(colors: [
                                    Colors.red,
                                    Colors.redAccent
                                  ])
                                      : const LinearGradient(colors: [
                                    AppColors.primary,
                                    Colors.pinkAccent
                                  ]),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isRecording
                                          ? Colors.red
                                          : AppColors.primary)
                                          .withOpacity(0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isRecording
                                      ? Icons.stop_rounded
                                      : (_messageController.text.trim().isEmpty
                                      ? Icons.mic_rounded
                                      : Icons.send_rounded),
                                  color: Colors.white,
                                  size: 22,
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
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final bool isMe = msg['senderId'] == currentUser!.uid;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
            colors: [AppColors.primary, Colors.pinkAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isMe ? null : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft:
            isMe ? const Radius.circular(22) : const Radius.circular(4),
            bottomRight:
            isMe ? const Radius.circular(4) : const Radius.circular(22),
          ),
          boxShadow: [
            BoxShadow(
              color: isMe
                  ? AppColors.primary.withOpacity(0.25)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft:
            isMe ? const Radius.circular(22) : const Radius.circular(4),
            bottomRight:
            isMe ? const Radius.circular(4) : const Radius.circular(22),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (msg['type'] == 'text')
                    Text(
                      msg['text'] ?? '',
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (msg['type'] == 'image')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: msg['mediaUrl'].toString().startsWith('http')
                          ? Image.network(msg['mediaUrl'],
                          height: 190, fit: BoxFit.cover)
                          : Image.file(File(msg['mediaUrl']),
                          height: 190, fit: BoxFit.cover),
                    ),
                  if (msg['type'] == 'audio')
                    GestureDetector(
                      onTap: () => _playAudio(msg['mediaUrl']),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Colors.white.withOpacity(0.2)
                                  : AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              (_isPlaying &&
                                  _currentlyPlayingPath == msg['mediaUrl'])
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: isMe ? Colors.white : AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            msg['text'] ?? 'Voice Note',
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}