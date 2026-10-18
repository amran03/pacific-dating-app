import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_color.dart';
import '../../../core/services/chat_cache_service.dart';
import '../../../core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/services/connectivity_service.dart';
import '../../../core/services/unread_messages_service.dart';
import '../../../core/services/core_error_service.dart';
import '../../../core/widgets/heart_loader.dart';
import '../../../core/widgets/no_internet_view.dart';
import '../../chat/domain/models/chat_model.dart';
import '../../profile/presentation/public_profile_screen.dart';
import 'individual_chat_screen.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final MatchmakingService _matchmakingService = MatchmakingService();

  // ---- UNREAD COUNTS (per chat) ----
  // Hesabu zinatoka UnreadMessagesService (subscription MOJA ya app yote).
  // Hapa tunasikiliza stream tayari ili badges za kila mazungumzo
  // zijisasisha papo hapo count inapobadilika (k.m. mtumiaji akifungua
  // ujumbe -> openChat() inafuta count moja kwa moja).
  StreamSubscription<Map<String, int>>? _countsSub;

  // ---- BACKGROUND REFRESH + OFFLINE CACHE ----
  // Stream imewekwa HAPA (si kwenye build) — kila rebuild (badge update)
  // zamani ilifungua subscription MPYA na kila kitu kikawa kina-refresh
  // full-page. Sasa ni background: subscription moja, rebuild ndogo tu.
  Stream<List<ChatModel>>? _chatsStream;

  // Cache ya ndani (storage ya simu) — offline au stream imeshindwa:
  // orodha ya mazungumzo bado inaonekana (bila loader/errors za ukurasa
  // mzima). Inasasishwa background kila data halisi inapowasili.
  List<ChatModel> _cachedChats = const [];

  @override
  void initState() {
    super.initState();
    _chatsStream = _matchmakingService.streamMyChatRooms();
    _loadCachedChats();
    _countsSub = UnreadMessagesService.instance.countsStream.listen((_) {
      if (!mounted) return;
      // Hesabu zinasomwa moja kwa moja kutoka service kwenye [_unreadFor].
      setState(() {});
    });
  }

  Future<void> _loadCachedChats() async {
    final String uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final cached = await ChatCacheService.instance.loadChats(uid);
    if (!mounted || cached.isEmpty) return;
    setState(() => _cachedChats = cached);
  }

  /// "Jaribu tena" (kutoka NoInternetView) — sasisha mtandao + fungua upya
  /// stream. UI haionyeshi loader wa ukurasa mzima — inasubiri background.
  Future<void> _refreshChats() async {
    unawaited(ConnectivityService.instance.refresh());
    _chatsStream = _matchmakingService.streamMyChatRooms();
    if (mounted) setState(() {});
  }

  int _unreadFor(ChatModel chat) =>
      UnreadMessagesService.instance.unreadFor(chat.id);

  @override
  void dispose() {
    _countsSub?.cancel();
    super.dispose();
  }

  /// Moja ya logic ya kufungua chat (inatumika na list, matches na
  /// missed calls): locked -> dialog ya coins, wazi -> moja to moja.
  void _openChat(ChatModel chat) {
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
  }

  void _showUnlockDialog(ChatModel chat) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: AppRadius.xl,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: AppRadius.xl,
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
                    child: const Icon(Icons.lock_rounded, color: AppColors.coinGoldDark, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Unlock Chat with ${chat.name}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Use ${chat.unlockCostCoins} Pacific Coins to unlock this conversation. It's a ONE-TIME payment — the chat stays open forever!",
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
                              showAppNotification(context, "Chat with ${chat.name} Unlocked Successfully!", color: Colors.green);
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
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
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

          // Main Content — background refresh: stream MOJA kutoka initState.
          // Offline/stream imeshindwa -> cache ya ndani inaonekana (hakuna
          // loader wa ukurasa mzima). Error inaonyeshwa TU iwapo hakuna
          // data kabisa (NoInternetView ndogo yenye "Jaribu tena").
          StreamBuilder<List<ChatModel>>(
            stream: _chatsStream,
            builder: (context, snapshot) {
              List<ChatModel> chats = snapshot.data ?? [];

              if (snapshot.hasData && chats.isNotEmpty) {
                // Data halisi imewasili — sasisha cache background.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final String uid =
                      Supabase.instance.client.auth.currentUser?.id ?? '';
                  ChatCacheService.instance.saveChats(uid, chats);
                  if (_cachedChats.length != chats.length) {
                    _cachedChats = chats;
                  }
                });
              }

              if (snapshot.hasError && chats.isEmpty) {
                if (_cachedChats.isNotEmpty) {
                  // Refresh imeshindwa background — onyesha cache kimya.
                  chats = _cachedChats;
                } else {
                  // Hakuna data kabisa + hakuna internet — onyesha error
                  // ndogo tu (si ukurasa mzima wa hitilafu).
                  return Center(
                    child: SingleChildScrollView(
                      child: NoInternetView(onRetry: _refreshChats),
                    ),
                  );
                }
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  chats.isEmpty) {
                if (_cachedChats.isNotEmpty) {
                  // Bado tunasubiri mtandao — onyesha cache, refresh
                  // inaendelea background.
                  chats = _cachedChats;
                } else {
                  return const Center(child: HeartLoader(size: 64));
                }
              }

              if (chats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 70, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        "No conversations yet",
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Match with someone in Discover and you can\nstart chatting here.",
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

                  // ---- MISSED CALLS SECTION ----
                  _MissedCallsSection(
                    onOpenChat: _openChat,
                    onOpenLockedChat: _showUnlockDialog,
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
                                            // UNREAD BADGE — idadi ya messages
                                            // zisizosomwa za chat hii.
                                            if (_unreadFor(chat) > 0)
                                              Positioned(
                                                right: -2,
                                                top: -2,
                                                child: Badge.count(
                                                  count: _unreadFor(chat),
                                                  backgroundColor: Colors.redAccent,
                                                  largeSize: 14,
                                                  textStyle: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
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
                              borderRadius: AppRadius.card,
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
                              borderRadius: AppRadius.card,
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
                                    trailing: _unreadFor(chat) > 0
                                        ? Badge.count(
                                            count: _unreadFor(chat),
                                            backgroundColor: Colors.redAccent,
                                            largeSize: 18,
                                            textStyle: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                            child: const Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              color: Colors.black38,
                                              size: 16,
                                            ),
                                          )
                                        : (chat.isLocked
                                            ? Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.coinGold.withValues(alpha: 0.15),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.lock_outline_rounded, color: AppColors.coinGoldDark, size: 20),
                                              )
                                            : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black38, size: 16)),
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

// ============================================================
// MISSED CALLS SECTION
// Inaonyesha simu zilizokosekana/kataliwa (kutoka notifications za
// type 'missed_call'). Row HAIFUTWI — inaashirwa imesomwa (read=true)
// mtumiaji akishaigusa, na inabaki kwenye history ikiwa greyed.
// ============================================================
class _MissedCallsSection extends StatelessWidget {
  final MatchmakingService _service = MatchmakingService();
  final void Function(ChatModel chat) onOpenChat;
  final void Function(ChatModel chat) onOpenLockedChat;

  _MissedCallsSection({
    required this.onOpenChat,
    required this.onOpenLockedChat,
  });

  String _timeAgo(dynamic ts) {
    DateTime? dt;
    if (ts is String) dt = DateTime.tryParse(ts);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Future<void> _openMissedCall(Map<String, dynamic> call) async {
    final String id = call['id']?.toString() ?? '';
    final String peerUid = call['from_uid']?.toString() ?? '';
    if (peerUid.isEmpty) return;

    // Inaashiria imesomwa MARA MOJA — row inabaki (haitafutwi).
    if (id.isNotEmpty) await _service.markNotificationRead(id);

    final access = await _service.getChatAccessInfo(peerUid);
    final bool unlocked = access['unlocked'] == true;
    final int price = (access['price'] ?? 0) as int;

    final chat = ChatModel(
      id: peerUid,
      name: call['from_name']?.toString().isNotEmpty == true
          ? call['from_name'].toString()
          : 'User',
      avatarUrl: '',
      lastMessage: call['description']?.toString() ?? '',
      timeSent: _timeAgo(call['created_at']),
      isLocked: !unlocked,
      unlockCostCoins: price,
    );

    if (unlocked) {
      onOpenChat(chat);
    } else {
      onOpenLockedChat(chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.streamMissedCalls(),
        builder: (context, snapshot) {
          final calls = snapshot.data ?? [];
          // None missed calls — section hazionyeshwi kabisa.
          if (calls.isEmpty) return const SizedBox.shrink();

          final int unreadCount =
              calls.where((c) => c['read'] != true).length;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Missed Calls',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: AppRadius.sm,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(right: 16),
                    itemCount: calls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final call = calls[index];
                      final bool isRead = call['read'] == true;
                      final bool isDeclined =
                          (call['title']?.toString() ?? '')
                              .contains('declined');

                      return Opacity(
                        // Imesomwa -> inaonekana "faded" kama history.
                        opacity: isRead ? 0.55 : 1.0,
                        child: GestureDetector(
                          onTap: () => _openMissedCall(call),
                          child: Container(
                            width: 150,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: AppRadius.md,
                              border: Border.all(
                                color: isRead
                                    ? Colors.grey.shade200
                                    : Colors.redAccent
                                        .withValues(alpha: 0.35),
                                width: isRead ? 1 : 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent
                                            .withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isDeclined
                                            ? Icons.phone_disabled_rounded
                                            : Icons.phone_missed_rounded,
                                        color: Colors.redAccent,
                                        size: 18,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (!isRead)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  call['from_name']?.toString().isNotEmpty ==
                                          true
                                      ? call['from_name'].toString()
                                      : 'User',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  '${_timeAgo(call['created_at'])} • ${isDeclined ? 'Declined' : 'Missed'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        isRead ? Colors.grey : Colors.redAccent,
                                    fontWeight: isRead
                                        ? FontWeight.w400
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}