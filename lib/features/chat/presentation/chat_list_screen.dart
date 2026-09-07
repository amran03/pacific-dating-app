import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/constants/app_color.dart';
import '../../../core/services/matchmaking_service.dart';
import '../../../core/services/core_error_service.dart';
import '../../chat/domain/models/chat_model.dart';
import '../../profile/presentation/public_profile_screen.dart';
import 'individual_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final MatchmakingService _matchmakingService = MatchmakingService();

  void _showUnlockDialog(ChatModel chat) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.coinGold.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: AppColors.coinGold, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Unlock Chat with ${chat.name}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Maongezi haya yatafungwa pindi dakika 30 zikiisha. Tuma Gift au tumia ${chat.unlockCostCoins} Pasific Coins ili kufungua maongezi ya daima!",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.4, fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Baadaye", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            if (!context.mounted) return;
                            try {
                              await _matchmakingService.payAndUnlockChat(chat.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Chat with ${chat.name} Unlocked Successfully!"),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              CoreErrorService().showError(
                                context,
                                CoreErrorService().mapExceptionToMessage(e),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text("Unlock (${chat.unlockCostCoins} Coins)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: Stack(
        children: [
          // Background Aesthetic Decorative Orbs
          Positioned(
            top: -40,
            left: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            top: 250,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.pinkAccent.withValues(alpha: 0.08),
              ),
            ),
          ),

          // Main Content
          StreamBuilder<List<ChatModel>>(
            stream: _matchmakingService.streamMyChatRooms(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }

              if (snapshot.hasError) {
                // Mara nyingi hii ni kwa sababu Firestore Composite Index
                // bado haijajengwa. Angalia debug console - Firebase
                // hutoa LINK ya moja kwa moja ya kujenga index, bonyeza tu.
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      "Imeshindikana kupakua mazungumzo: ${snapshot.error}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                );
              }

              final chats = snapshot.data ?? [];

              if (chats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 70, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        "Bado hakuna mazungumzo",
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Pendana na mtu kwenye Discover ili muanze\nkuongea hapa.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Glassmorphism App Bar
                  SliverAppBar(
                    floating: true,
                    pinned: true,
                    backgroundColor: Colors.white.withValues(alpha: 0.7),
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    flexibleSpace: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ),
                    title: const Text(
                      "Messages",
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                    actions: [
                      Container(
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.search_rounded, color: Colors.black87),
                          onPressed: () {
                            // Implement search functionality here if needed
                          },
                        ),
                      ),
                    ],
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // New Matches Header
                          const Text(
                            "New Matches",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                          ),
                          const SizedBox(height: 12),

                          // Horizontal Matches List
                          SizedBox(
                            height: 95,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: chats.length,
                              itemBuilder: (context, index) {
                                final chat = chats[index];
                                return GestureDetector(
                                  onTap: () {
                                    if (chat.isLocked) {
                                      _showUnlockDialog(chat);
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => IndividualChatScreen(chat: chat),
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 16),
                                    child: Column(
                                      children: [
                                        Stack(
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: const LinearGradient(
                                                  colors: [AppColors.primary, Colors.pinkAccent],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppColors.primary.withValues(alpha: 0.3),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              padding: const EdgeInsets.all(2),
                                              child: CircleAvatar(
                                                radius: 30,
                                                backgroundImage: NetworkImage(chat.avatarUrl),
                                              ),
                                            ),
                                            if (chat.isLocked)
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: const BoxDecoration(
                                                    color: AppColors.coinGold,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          chat.name,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Text(
                            "Conversations",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),

                  // Chats List (SliverList for better performance)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final chat = chats[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => PublicProfileScreen(uid: chat.id),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.08),
                                              blurRadius: 6,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: CircleAvatar(
                                          radius: 26,
                                          backgroundImage: NetworkImage(chat.avatarUrl),
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          chat.name,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87),
                                        ),
                                        Text(
                                          chat.timeSent,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: chat.isLocked ? Colors.redAccent : Colors.black45,
                                            fontWeight: chat.isLocked ? FontWeight.w800 : FontWeight.w300,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6.0),
                                      child: Text(
                                        chat.lastMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: chat.isLocked ? AppColors.coinGold : Colors.black54,
                                          fontWeight: chat.isLocked ? FontWeight.w800 : FontWeight.w300,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    trailing: chat.isLocked
                                        ? Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.coinGold.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.lock_outline_rounded, color: AppColors.coinGold, size: 20),
                                    )
                                        : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black38, size: 16),
                                    onTap: () {
                                      if (chat.isLocked) {
                                        _showUnlockDialog(chat);
                                      } else {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => IndividualChatScreen(chat: chat),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: chats.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}