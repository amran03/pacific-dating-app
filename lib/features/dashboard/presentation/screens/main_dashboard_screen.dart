import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/gift_model.dart';
import 'package:pacific_dating_app/features/chat/presentation/widgets/gift_modal_bottom_sheet.dart';
import 'package:pacific_dating_app/features/chat/presentation/individual_chat_screen.dart';
import 'package:pacific_dating_app/features/profile/presentation/public_profile_screen.dart';

// Imports za Screen zako kutoka kwenye folda husika
import 'package:pacific_dating_app/features/chat/presentation/chat_list_screen.dart';
import 'package:pacific_dating_app/features/chat/presentation/likes_screen.dart';
import 'package:pacific_dating_app/features/profile/presentation/profile_screen.dart';
import 'package:pacific_dating_app/features/profile/presentation/screens/search_screen.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  int _currentIndex = 0;

  // Screens zilizounganishwa na mafaili yako halisi ikiwemo ProfileScreen
  final List<Widget> _screens = [
    const DiscoverTab(),
    const LikesScreen(),     // Kutoka likes_screen.dart
    const ChatListScreen(),  // Kutoka chat_list_screen.dart
    const ProfileScreen(),   // <--- Imeunganishwa rasmi hapa!
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        elevation: 12,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11.5),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_rounded),
            label: "Discover",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_rounded),
            label: "Likes",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded),
            label: "Chat",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

// --- NOTIFICATION SCREEN ---
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  // Kila 'type' ina icon na rangi yake - inatumika kupamba arifa halisi
  // zinazotoka Supabase (badala ya kuwa hardcoded).
  static const Map<String, Map<String, dynamic>> _typeStyles = {
    'gift': {'icon': Icons.card_giftcard_rounded, 'color': Colors.pink},
    'coins': {'icon': Icons.monetization_on_rounded, 'color': Colors.amber},
    'match': {'icon': Icons.favorite_rounded, 'color': Colors.redAccent},
    'message': {'icon': Icons.chat_bubble_rounded, 'color': Colors.blue},
  };

  String _formatTimeAgo(dynamic ts) {
    if (ts == null) return '';
    DateTime? dt;
    if (ts is String) {
      dt = DateTime.tryParse(ts);
    } else if (ts is DateTime) {
      dt = ts;
    }
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Sasa hivi';
    if (diff.inMinutes < 60) return 'Dk ${diff.inMinutes} zilizopita';
    if (diff.inHours < 24) return 'Saa ${diff.inHours} zilizopita';
    if (diff.inDays == 1) return 'Jana';
    return '${diff.inDays} siku zilizopita';
  }

  @override
  Widget build(BuildContext context) {
    final String myUid = Supabase.instance.client.auth.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Notifications",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('to_uid', myUid)
            .order('created_at', ascending: false)
            .limit(50),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Imeshindikana kupakua arifa: ${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          }

          final docs = snapshot.data ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_none_rounded, size: 70, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "Bado hakuna arifa",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Arifa za gifts, matches, na coins\nzitaonekana hapa.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index];
              final String type = data['type'] ?? 'coins';
              final style = _typeStyles[type] ?? _typeStyles['coins']!;
              final Color themeColor = style['color'];

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(style['icon'], color: themeColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  data['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTimeAgo(data['created_at']),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            data['description'] ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- CHAT ACCESS BUTTON ---
class ChatAccessButton extends StatefulWidget {
  final String uid;
  final String name;
  final String image;

  const ChatAccessButton({
    super.key,
    required this.uid,
    required this.name,
    required this.image,
  });

  @override
  State<ChatAccessButton> createState() => _ChatAccessButtonState();
}

class _ChatAccessButtonState extends State<ChatAccessButton> {
  final MatchmakingService _matchmakingService = MatchmakingService();
  late Future<Map<String, dynamic>> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _matchmakingService.getChatAccessInfo(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _accessFuture,
      builder: (context, snapshot) {
        final bool isUnlocked = snapshot.data?['unlocked'] ?? false;
        final int price = snapshot.data?['price'] ?? 0;
        final bool canChat = isUnlocked || price <= 0;

        return GestureDetector(
          onTap: () {
            if (canChat) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => IndividualChatScreen(
                    chat: ChatModel(
                      id: widget.uid,
                      name: widget.name,
                      avatarUrl: widget.image,
                      lastMessage: '',
                      timeSent: '',
                    ),
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PublicProfileScreen(uid: widget.uid),
                ),
              );
            }
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: canChat
                  ? const LinearGradient(
                      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                    )
                  : LinearGradient(
                      colors: [Colors.grey.shade700, Colors.grey.shade900],
                    ),
              boxShadow: [
                BoxShadow(
                  color: (canChat ? Colors.green : Colors.black).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  canChat ? Icons.chat_bubble_rounded : Icons.lock_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                if (!canChat && price > 0)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "$price",
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- DISCOVER TAB ---
class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  int _topCardIndex = 0;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  final MatchmakingService _matchmakingService = MatchmakingService();

  // Data halisi ya watumiaji kutoka Firestore (imejazwa kwenye initState).
  // Muundo wa Map umebaki sawa na ule wa awali ili UI isibadilike.
  List<Map<String, dynamic>> _profiles = [];

  // INFINITE SWIPE: profiles zilizoshakuwa swiped - zinatumika kuzungusha
  // (recycle) swipe zikishaisha watu halisi wote, ili stack zisiishe kamwe.
  final List<Map<String, dynamic>> _swipedProfiles = [];

  @override
  void initState() {
    super.initState();
    _loadDiscoverableUsers();
  }

  Future<void> _loadDiscoverableUsers() async {
    setState(() => _isLoading = true);
    try {
      // Pata coordinates zangu mwenyewe (zilizohifadhiwa wakati wa
      // SetupAccountScreen) ili kuhesabu umbali halisi kwa kila mtu.
      final UserModel? me = await _matchmakingService.fetchMyProfile();

      final List<UserModel> users =
      await _matchmakingService.fetchDiscoverableUsers();

      setState(() {
        _profiles = _mapUsersToProfiles(users, me);
        _topCardIndex = 0;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imeshindikana kupakua watumiaji: $e")),
        );
      }
    }
  }

  /// INFINITE SWIPE: Inapakia watumiaji wapya kwenye stack KWA BACKGROUND,
  /// bila mtumiaji kusimama kusubiri. Kama watumiaji wote waliopo kwenye
  /// Firestore wameisha (hakuna mpya), tunarudisha (recycle) wale
  /// walioshakuwa swiped kwa mpangilio mpya - swipe zisiishe kamwe.
  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final UserModel? me = await _matchmakingService.fetchMyProfile();

      final List<UserModel> users =
      await _matchmakingService.fetchDiscoverableUsers();

      final knownUids = _profiles
          .map((p) => p['uid'] as String?)
          .whereType<String>()
          .toSet();

      final List<Map<String, dynamic>> fresh =
      _mapUsersToProfiles(users, me)
          .where((p) => !knownUids.contains(p['uid']))
          .toList();

      if (mounted) {
        setState(() {
          if (fresh.isNotEmpty) {
            _profiles.addAll(fresh);
          } else if (_swipedProfiles.isNotEmpty) {
            // RECYCLE: changanya waliopita ili mtumiaji aendelee kupiga
            // swipe bila mwisho (behavior ya pro dating apps).
            final List<Map<String, dynamic>> recycled =
            [..._swipedProfiles]..shuffle();
            _profiles.addAll(recycled);
          }
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  List<Map<String, dynamic>> _mapUsersToProfiles(
      List<UserModel> users,
      UserModel? me,
      ) {
    return users
        .map((u) {
      String locationLabel = "Tanzania";

      if (me?.latitude != null &&
          me?.longitude != null &&
          u.latitude != null &&
          u.longitude != null) {
        final double distanceKm = MatchmakingService.calculateDistanceKm(
          me!.latitude!,
          me.longitude!,
          u.latitude!,
          u.longitude!,
        );
        locationLabel = distanceKm < 1
            ? "Chini ya 1km"
            : "${distanceKm.toStringAsFixed(0)}km";
      }

      return {
        'uid': u.uid,
        'name': u.name,
        'age': u.age,
        'location': locationLabel,
        'image': (u.profileImageUrl != null && u.profileImageUrl!.isNotEmpty)
            ? u.profileImageUrl!
            : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=600',
        'isMatched': false,
        'chatUnlockPrice': u.chatUnlockPrice,
      };
    })
        .toList();
  }

  /// isLike=true (swipe juu / gift) -> Like halisi. isLike=false (swipe
  /// chini) -> Pass. Baada ya animation, profile inatolewa kwenye stack
  /// (haizunguki tena kwa sababu sasa ni watu halisi, sio dummy data).
  void _swipeVertical(bool isLike) {
    if (_profiles.isEmpty || _topCardIndex >= _profiles.length) return;

    final swipedProfile = _profiles[_topCardIndex];
    final String? targetUid = swipedProfile['uid'] as String?;

    setState(() {
      _dragOffset = Offset(0, isLike ? -800 : 800);
      _isDragging = false;
    });

    // Andika like/pass Firestore - haizuii UI isubiri
    if (targetUid != null) {
      _matchmakingService.recordSwipe(targetUid, isLike: isLike).then((isMutualMatch) {
        if (isMutualMatch && mounted) {
          _showMatchDialog(swipedProfile);
        }
      }).catchError((e) {
        debugPrint("Swipe recording error: $e");
      });
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        if (_profiles.isNotEmpty && _topCardIndex < _profiles.length) {
          // INFINITE SWIPE: tunahifadhi profile iliyopita kwa ajili ya
          // recycle — swipe hazisishi kamwe.
          _swipedProfiles.add(_profiles.removeAt(_topCardIndex));
        }
        _dragOffset = Offset.zero;
      });

      // Stack ikianza kuwa ndogo (cards ≤ 3 zilizobaki), pakia wapya
      // BACKGROUND bila mtumiaji kuona loading ya kusimamisha.
      if (_profiles.length - _topCardIndex <= 3) {
        _loadMoreUsers();
      }
    });
  }

  void _showMatchDialog(Map<String, dynamic> profile) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                const SizedBox(height: 10),
                const Text(
                  "Umepata Match!",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(image: NetworkImage(profile['image']), fit: BoxFit.cover),
                    border: Border.all(color: AppColors.primary, width: 3),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Wewe na ${profile['name']} mmependana! Anzeni mazungumzo sasa.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => IndividualChatScreen(
                            chat: ChatModel(
                              id: profile['uid'],
                              name: profile['name'],
                              avatarUrl: profile['image'],
                              lastMessage: '',
                              timeSent: '',
                            ),
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Anza Kuongea", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Endelea Kutafuta", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openGiftBottomSheet(BuildContext context, Map<String, dynamic> profile) {
    GiftModalBottomSheet.show(
      context,
      recipientUid: profile['uid'],
      recipientName: profile['name'],
      onGiftSent: (gift) {
        _showGiftSentAnimation(profile['name'], gift);
      },
    );
  }

  void _showGiftSentAnimation(String recipientName, GiftModel gift) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          gift.imageUrl != null
                              ? Image.network(
                                  gift.imageUrl!,
                                  width: 100,
                                  height: 100,
                                  errorBuilder: (_, __, ___) => Text(
                                    gift.emoji ?? '🎁',
                                    style: const TextStyle(fontSize: 90),
                                  ),
                                )
                              : Text(
                                  gift.emoji ?? '🎁',
                                  style: const TextStyle(fontSize: 90),
                                ),
                          const SizedBox(height: 12),
                          Text(
                            "Zawadi Imetumwa!",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Umemtumia $recipientName ${gift.name} kikamilifu",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context);
        _swipeVertical(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double dragProgress = (_dragOffset.dy / 300).clamp(-1.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_active_rounded, color: Colors.black87, size: 26),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationScreen()),
                );
              },
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        title: Text(
          "Pacific Discover",
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.black87, size: 26),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _profiles.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.explore_off_rounded, size: 70, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  "Hakuna watumiaji wapya kwa sasa",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Rudi baadaye kuona watumiaji wapya waliojiunga.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadDiscoverableUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("Onyesha Tena", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          )
              : Stack(
            children: [
              // BACK CARD
              if (_topCardIndex + 1 < _profiles.length)
                Positioned.fill(
                  child: AnimatedScale(
                    scale: 0.9 + (dragProgress.abs() * 0.1),
                    duration: const Duration(milliseconds: 200),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: (1.0 - dragProgress.abs()) * 10,
                        sigmaY: (1.0 - dragProgress.abs()) * 10,
                      ),
                      child: _buildCardUI(_profiles[_topCardIndex + 1], isFront: false),
                    ),
                  ),
                ),

              // FRONT CARD
              Positioned.fill(
                child: GestureDetector(
                  onVerticalDragStart: (_) => setState(() => _isDragging = true),
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _dragOffset += Offset(0, details.delta.dy);
                    });
                  },
                  onVerticalDragEnd: (details) {
                    if (_dragOffset.dy < -130) {
                      _swipeVertical(true);
                    } else if (_dragOffset.dy > 130) {
                      _swipeVertical(false);
                    } else {
                      setState(() {
                        _dragOffset = Offset.zero;
                        _isDragging = false;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(0, _dragOffset.dy, 0)
                      ..rotateZ(_dragOffset.dy * 0.0003),
                    child: Stack(
                      children: [
                        _buildCardUI(_profiles[_topCardIndex], isFront: true),

                        // LIKE / PASS stamps — zinaonekana unapovuta kadi
                        // (pro touch ya dating apps kama Tinder).
                        IgnorePointer(
                          child: _buildDragStamps(dragProgress),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // INFINITE SWIPE: indicator ndogo inayoonyesha profile mpya
              // zinapakia background — mtumiaji hajui, anaendelea kupiga.
              if (_isLoadingMore)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Inaleta watumiaji wapya...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// LIKE / PASS stamps zinazoonekana wakati wa kuvuta kadi (vertical).
  Widget _buildDragStamps(double dragProgress) {
    final double likeOpacity =
        ((-dragProgress - 0.2) / 0.45).clamp(0.0, 1.0);
    final double passOpacity =
        ((dragProgress - 0.2) / 0.45).clamp(0.0, 1.0);

    Widget stamp({
      required String label,
      required IconData icon,
      required Color color,
      required double opacity,
      required double rotation,
    }) {
      return Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: rotation,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        if (likeOpacity > 0)
          Positioned(
            top: 44,
            left: 28,
            child: stamp(
              label: "LIKE",
              icon: Icons.favorite_rounded,
              color: AppColors.success,
              opacity: likeOpacity,
              rotation: -0.22,
            ),
          ),
        if (passOpacity > 0)
          Positioned(
            top: 44,
            right: 28,
            child: stamp(
              label: "PASS",
              icon: Icons.close_rounded,
              color: AppColors.error,
              opacity: passOpacity,
              rotation: 0.22,
            ),
          ),
      ],
    );
  }

  Widget _buildCardUI(Map<String, dynamic> profile, {required bool isFront}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        image: DecorationImage(
          image: NetworkImage(profile['image']),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.9),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: isFront && profile['uid'] != null
                      ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PublicProfileScreen(uid: profile['uid']),
                      ),
                    );
                  }
                      : null,
                  child: Row(
                    children: [
                      Text(
                        "${profile['name']}, ${profile['age']}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (isFront) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      profile['location'],
                      style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (isFront)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openGiftBottomSheet(context, profile),
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF416C).withValues(alpha: 0.5),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.card_giftcard_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  "Send Gift",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ChatAccessButton(
                        uid: profile['uid'],
                        name: profile['name'],
                        image: profile['image'],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}