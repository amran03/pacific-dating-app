import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/core/widgets/heart_loader.dart';
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
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';
import 'package:pacific_dating_app/core/services/profile_photo_service.dart';
import 'package:pacific_dating_app/core/services/unread_messages_service.dart';

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
    const ProfileScreen(),   // <--- Officially integrated here!
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
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_rounded),
            label: "Discover",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_rounded),
            label: "Likes",
          ),
          const BottomNavigationBarItem(
            icon: _ChatTabIcon(),
            label: "Chat",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}

/// Icon ya Chat kwenye BottomNavigationBar yenye badge ya idadi ya
/// messages zisizosomwa (receiver_id = mimi na seen = false).
///
/// Hesabu zinatoka UnreadMessagesService — stream MOJA iliyoshirikishwa
/// na chat list (zamani kila build ilifungua subscription MPYA ya
/// realtime — leak + badge haiondoki kamwe).
class _ChatTabIcon extends StatelessWidget {
  const _ChatTabIcon();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, int>>(
      stream: UnreadMessagesService.instance.countsStream,
      initialData: UnreadMessagesService.instance.counts,
      builder: (context, snapshot) {
        final int unread = (snapshot.data ?? const <String, int>{})
            .values
            .fold(0, (sum, n) => sum + n);
        const icon = Icon(Icons.chat_bubble_rounded);
        if (unread <= 0) return icon;
        return Badge.count(
          count: unread, // automatically shows "99+" for large numbers
          child: icon,
        );
      },
    );
  }
}

// --- NOTIFICATION SCREEN ---
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  // Kila 'type' ina icon na rangi yake - inatumika kupamba arifa halisi
  // zinazotoka Supabase (badala ya kuwa hardcoded).
  // NOTE: hakuna 'message' hapa — arifa za messages zinaonyeshwa kwenye
  // tab ya Chat/pekee; notification page inaonyesha matukio mengine tu
  // (gifts, matches, coins, missed calls...).
  static const Map<String, Map<String, dynamic>> _typeStyles = {
    'gift': {'icon': Icons.card_giftcard_rounded, 'color': Colors.pink},
    'coins': {'icon': Icons.monetization_on_rounded, 'color': Colors.amber},
    'match': {'icon': Icons.favorite_rounded, 'color': Colors.redAccent},
    'missed_call': {
      'icon': Icons.phone_missed_rounded,
      'color': Colors.redAccent,
    },
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
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return 'Dk ${diff.inMinutes} zilizopita';
    if (diff.inHours < 24) return 'Saa ${diff.inHours} zilizopita';
    if (diff.inDays == 1) return 'Jana';
    return '${diff.inDays} siku zilizopita';
  }

  @override
  Widget build(BuildContext context) {
    final String myUid = Supabase.instance.client.auth.currentUser?.id ?? '';

    // Real read receipts: mark everything as read once the user opens
    // the notifications screen (idempotent, safe to call on rebuilds).
    if (myUid.isNotEmpty) {
      Supabase.instance.client
          .from('notifications')
          .update({'read': true})
          .eq('to_uid', myUid)
          .eq('read', false)
          // Arifa za 'message' haziashiriwi kusomwa hapa — zinaashiriwa
          // pale chat yenyewe inapofunguliwa (badge ya chat ndiyo ya
          // kuaminika; opening the notification page HASITANGAZI messages
          // kuwa zimesomwa).
          .neq('type', 'message')
          .then((_) {}, onError: (e) => debugPrint('Mark-as-read failed: $e'));
    }

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
            // MESSAGES ZINA MAHALI PAKE PALE PEKEE: tab ya Chat. Arifa za
            // type 'message' hazionyeshwi hapa — page hii inaonyesha
            // matukio mengine tu (gifts, matches, coins, missed calls).
            .neq('type', 'message')
            .order('created_at', ascending: false)
            .limit(50),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: HeartLoader(size: 64));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Failed to load notifications: ${snapshot.error}",
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
                    "No notifications yet",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Notifications about gifts, matches, and coins\nwill appear here.",
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
              // Read vs unread: arifa hazifutwi — zinaashiriwa imesomwa
              // (greyed + bila dot nyekundu) mtumiaji akishaiziona.
              final bool isRead = data['read'] == true;

              return Opacity(
                opacity: isRead ? 0.65 : 1.0,
                child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.card,
                  border: isRead
                      ? Border.all(color: Colors.grey.shade200)
                      : Border.all(
                          color: themeColor.withValues(alpha: 0.35),
                          width: 1.4,
                        ),
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(style['icon'], color: themeColor, size: 26),
                        ),
                        // Dot nyekundu = bado haijasomwa
                        if (!isRead)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: themeColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
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
                        borderRadius: AppRadius.sm,
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

  // PHOTO BROWSING (swipe kushoto/kulia): picha za kila profile (max 6)
  // zilizopangwa kwa position. Key = uid; value = URLs (0 = picha ya mbele).
  final Map<String, List<String>> _photoCache = {};
  final Set<String> _photoLoadingUids = {};
  int _photoIndex = 0; // picha inayoonekana kwenye card ya mbele sasa

  @override
  void initState() {
    super.initState();
    _loadDiscoverableUsers();
  }

  Future<void> _loadDiscoverableUsers() async {
    // Keep old cards on screen while retrying: only show the spinner on the
    // very first load (fixes "Show Again still says failed" UX).
    final bool firstLoad = _profiles.isEmpty;
    if (firstLoad) setState(() => _isLoading = true);
    try {
      // My own coordinates (saved during SetupAccountScreen) for real
      // distance labels on each card. NON-FATAL: if this fails we still
      // load people (distance then falls back to a generic label) instead
      // of failing the whole Discover screen.
      UserModel? me;
      try {
        me = await _matchmakingService.fetchMyProfile();
      } catch (_) {
        me = null;
      }

      final List<UserModel> users =
      await _matchmakingService.fetchDiscoverableUsers();

      if (!mounted) return;
      setState(() {
        final List<Map<String, dynamic>> mapped =
            _mapUsersToProfiles(users, me);
        if (mapped.isNotEmpty) {
          _profiles = mapped;
        } else if (_swipedProfiles.isNotEmpty) {
          // "Show Again" with no NEW people: re-show the people we already
          // saw (with their ratings) instead of an empty/failed screen.
          _profiles = [..._swipedProfiles]..shuffle();
          _swipedProfiles.clear();
        } else {
          _profiles = mapped;
        }
        _topCardIndex = 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Error must NEVER wipe existing people: if we already have cards,
      // keep showing them and only toast the error. If we have previously
      // swiped profiles and nothing else, re-show those instead of an
      // empty failure screen.
      if (_profiles.isEmpty && _swipedProfiles.isNotEmpty) {
        setState(() {
          _profiles.addAll([..._swipedProfiles]..shuffle());
          _topCardIndex = 0;
        });
      }
      final msg = e.toString().replaceFirst('Exception: ', '');
      showAppNotification(context, msg.isEmpty ? 'Failed to load users. Please tap Show Again.' : msg);
    }
  }

  /// INFINITE SWIPE: loads new users into the stack IN THE BACKGROUND,
  /// without blocking the user. When all real users are exhausted,
  /// recycles previously swiped ones in a new order — swipes never end.
  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      // Best-effort: a profile fetch failure must NOT fail the
      // background refresh — fall back to null "me".
      UserModel? me;
      try {
        me = await _matchmakingService.fetchMyProfile();
      } catch (_) {
        me = null;
      }

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
            // RECYCLE: shuffle past profiles so the user can keep swiping
            // endlessly (pro dating-app behavior).
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
            ? "Less than 1km"
            : "${distanceKm.toStringAsFixed(0)}km";
      }

      return {
        'uid': u.uid,
        'name': u.name,
        'age': u.age,
        'location': locationLabel,
        // Empty string -> real initials/avatar fallback in _buildCardUI.
        'image': (u.profileImageUrl != null && u.profileImageUrl!.isNotEmpty)
            ? u.profileImageUrl!
            : '',
        'isMatched': false,
        'chatUnlockPrice': u.chatUnlockPrice,
        // Likes + gifts directly on the Discover card
        // (no extra query — counters from the users row).
        'likesCount': u.likesReceivedCount,
        'giftsCount': u.giftsReceivedCount,
      };
    })
        .toList();
  }

  /// SWIPE = SCROLL TU (hairiasi ya "like"). Swipe juu/chini inasogeza
  /// card moja mbele — HAIANDIKI chochote kwenye database. Kupendana
  /// (like/match) kunarekodiwa TU kupitia kitufe cha "Match" cha kwenye
  /// card ([_likeProfile]) — tazama chini.
  /// Picha za card ya mbele (max 6, kwa position). Fallback: picha ya mbele
  /// (profile['image']) kama profile_photos hazijapakiwa/hazipo.
  List<String> _cardPhotoUrls(Map<String, dynamic> profile) {
    final String uid = (profile['uid'] as String?) ?? '';
    final String image = (profile['image'] as String?) ?? '';
    final cached = _photoCache[uid];
    if (cached != null && cached.isNotEmpty) return cached;
    return image.isNotEmpty ? <String>[image] : <String>[];
  }

  /// Pakia picha za front-card (best-effort) na zionyeshe papo hapo.
  Future<void> _ensureFrontPhotos() async {
    if (_profiles.isEmpty || _topCardIndex >= _profiles.length) return;
    final String uid = (_profiles[_topCardIndex]['uid'] as String?) ?? '';
    if (uid.isEmpty) return;
    if (_photoCache.containsKey(uid) || _photoLoadingUids.contains(uid)) return;
    _photoLoadingUids.add(uid);
    try {
      final photos = await ProfilePhotoService.instance.fetchPhotos(uid);
      final urls = photos
          .map((p) => p.url)
          .where((u) => u.startsWith('http'))
          .toList();
      if (!mounted) return;
      // Hata ikiwa tupu, weka listing ili tusipakie tena; card itatumia fallback.
      setState(() => _photoCache[uid] = urls);
    } catch (_) {
      // Kimya — card inaonyesha picha ya mbele/fallback bila kupasuka.
    } finally {
      _photoLoadingUids.remove(uid);
    }
  }

  /// Swipe kushoto/kulia = kupapua picha 6 za mtu (SIO like/pass, SIO match).
  /// Index inazungushwa (wrap) ndani ya orodha ya picha zilizopo.
  void _cyclePhoto(int direction) {
    if (_profiles.isEmpty || _topCardIndex >= _profiles.length) return;
    final urls = _cardPhotoUrls(_profiles[_topCardIndex]);
    if (urls.length <= 1) return;
    setState(() {
      _photoIndex = (_photoIndex + direction) % urls.length;
      if (_photoIndex < 0) _photoIndex += urls.length;
      _dragOffset = Offset.zero;
      _isDragging = false;
    });
  }

  void _advanceCard() {
    if (_profiles.isEmpty || _topCardIndex >= _profiles.length) return;

    setState(() {
      _dragOffset = Offset.zero;
      _isDragging = false;
      _photoIndex = 0;
    });

    // Pila card iendele: profile iliyopita inahifadhiwa kwenye
    // _swipedProfiles ili iweze kurudishwa (INFINITE LOOP) badala ya
    // orodha kuisha.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        if (_profiles.isNotEmpty && _topCardIndex < _profiles.length) {
          _swipedProfiles.add(_profiles.removeAt(_topCardIndex));
        }
        _dragOffset = Offset.zero;

        // INFINITE LOOP: stack ikishaisha, rudi mwanzo (recycle) —
        // profiles zilizopitwa zinazungushwa tena kwa mpya.
        if (_profiles.isEmpty && _swipedProfiles.isNotEmpty) {
          _profiles.addAll([..._swipedProfiles]..shuffle());
          _swipedProfiles.clear();
          _topCardIndex = 0;
        }
      });

      // Stack ikipungua (<= 3 zilizo mbele), pakia mpya BACKGROUND
      // bila loader inayozuia mtumiaji.
      if (_profiles.length - _topCardIndex <= 3) {
        _loadMoreUsers();
      }
    });
  }

  /// MATCH button (kitufe cha moyo kwenye card): HII pekee ndiyo inayosajili
  /// "like" kwenye database na kuunda match pale pande zote mbili
  /// zimependana. Swipe ni scroll tu — haina maana ya kupendana.
  void _likeProfile(Map<String, dynamic> profile) {
    if (_profiles.isEmpty || _topCardIndex >= _profiles.length) return;

    // Only act on the FRONT card — background cards are not interactive.
    if (!identical(_profiles[_topCardIndex], profile)) return;

    final swipedProfile = _profiles[_topCardIndex];
    final String? targetUid = swipedProfile['uid'] as String?;

    setState(() {
      _dragOffset = Offset(0, -800);
      _isDragging = false;
      _photoIndex = 0;
    });

    if (targetUid != null) {
      _matchmakingService.recordSwipe(targetUid, isLike: true).then((isMutualMatch) {
        if (isMutualMatch && mounted) {
          _showMatchDialog(swipedProfile);
        }
      }).catchError((e) {
        debugPrint("Like recording error: $e");
      });
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        if (_profiles.isNotEmpty && _topCardIndex < _profiles.length) {
          _swipedProfiles.add(_profiles.removeAt(_topCardIndex));
        }
        _dragOffset = Offset.zero;

        // INFINITE LOOP: stack ikishaisha baada ya match, rudi mwanzo.
        if (_profiles.isEmpty && _swipedProfiles.isNotEmpty) {
          _profiles.addAll([..._swipedProfiles]..shuffle());
          _swipedProfiles.clear();
          _topCardIndex = 0;
        }
      });

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
              borderRadius: AppRadius.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                const SizedBox(height: 10),
                const Text(
                  "You got a Match!",
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
                  "You and ${profile['name']} liked each other! Start the conversation now.",
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
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                    ),
                    child: const Text("Start Chatting", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Keep Exploring", style: TextStyle(color: Colors.grey)),
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
                        borderRadius: AppRadius.xl,
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
                            "Gift Sent!",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "You sent to $recipientName ${gift.name} kikamilifu",
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
        // Gift imetumwa — endelea na card ijayo (swipe HAI-rekodi like).
        _advanceCard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double dragProgress = (_dragOffset.dy / 300).clamp(-1.0, 1.0);
    // Pakia picha za front-card (best-effort) ili swipe ya kushoto/kulia
    // iwe kupapua picha 6. Salama kwa sababu _ensureFrontPhotos inajilinda.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFrontPhotos());

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.auth.currentUser == null
              ? const Stream.empty()
              : Supabase.instance.client
                  .from('notifications')
                  .stream(primaryKey: ['id'])
                  .eq('to_uid', Supabase.instance.client.auth.currentUser!.id)
                  // Zilingane na NotificationScreen: arifa za 'message'
                  // hazihesabiwi kwenye bell hii (zina badge yake kwenye
                  // tab ya Chat).
                  .neq('type', 'message'),
          builder: (context, snapshot) {
            final int unreadCount = (snapshot.data ?? [])
                .where((n) => n['read'] != true)
                .length;

            return IconButton(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text('$unreadCount'),
                alignment: Alignment.topRight,
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.black87,
                  size: 26,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationScreen()),
                );
              },
            );
          },
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
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HeartLoader(size: 76),
                      SizedBox(height: 18),
                      Text(
                        "Looking for people near you...",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                )
              // Empty state only when there is truly NOBODY to show (no
              // fresh + no recycled profiles). With the INFINITE LOOP this
              // is rare — recycled profiles keep the cards coming back.
              : _profiles.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.explore_off_rounded, size: 70, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  "No new users right now",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Come back later to see new users who joined.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadDiscoverableUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                  ),
                  child: const Text("Show Again", style: TextStyle(color: Colors.white)),
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
                  onPanStart: (_) => setState(() => _isDragging = true),
                  onPanUpdate: (details) {
                    setState(() {
                      _dragOffset += details.delta;
                    });
                  },
                  onPanEnd: (details) {
                    // SWIPE JUU/CHINI = mtu mwingine (scroll tu, HAIANDIKI
                    // database, HAIANDIKI match). SWIPE KUSHOTO/KULIA =
                    // kupapua picha 6 za mtu (page ya picha), sio like/pass.
                    const double vThreshold = 130;
                    final double dx = _dragOffset.dx;
                    final double dy = _dragOffset.dy;
                    if (dy.abs() >= vThreshold && dy.abs() >= dx.abs()) {
                      _advanceCard();
                    } else if (dx.abs() >= 80) {
                      _cyclePhoto(dx < 0 ? 1 : -1);
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
                    // Horizontal ni DAMPED (0.25) ili isionekane kama like/pass;
                    // vertical ndio inasogeza card.
                    transform: Matrix4.translationValues(
                            _dragOffset.dx * 0.25, _dragOffset.dy, 0)
                      ..rotateZ(_dragOffset.dy * 0.0003),
                    child: Stack(
                      children: [
                        _buildCardUI(_profiles[_topCardIndex], isFront: true),
                      ],
                    ),
                  ),
                ),
              ),

              // INFINITE SWIPE: small indicator that new profiles are
              // loading in the background — the user just keeps swiping.
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
                        borderRadius: AppRadius.xl,
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
                            "Loading new users...",
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

  Widget _buildCardUI(Map<String, dynamic> profile, {required bool isFront}) {
    final String name = (profile['name'] as String?) ?? '';

    // Picha za profile (max 6) kwa position; index inazungushwa na swipe ya
    // kushoto/kulia. Fallback: picha ya mbele (profile['image']).
    final List<String> photos = _cardPhotoUrls(profile);
    final int count = photos.length;
    final int idx = count == 0 ? 0 : _photoIndex.clamp(0, count - 1).toInt();
    final String photoUrl = count == 0 ? '' : photos[idx];

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.xl,
        image: photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
                // Broken URL -> real avatar fallback instead of crash.
                onError: (_, __) {},
              )
            : null,
        color: photoUrl.isEmpty ? const Color(0xFF252525) : null,
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
          // Real avatar fallback: initials on a gradient background.
          if (photoUrl.isEmpty)
            Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 96,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          // PHOTO STRIP (Tinder-style): picha ngapi zimebaki + iliyopo.
          // Inaonekana kwenye front card tu wakati wa kupapua picha.
          if (isFront && count > 1)
            Positioned(
              top: 10,
              left: 14,
              right: 14,
              child: _photoStrip(count: count, index: idx),
            ),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.xl,
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
                const SizedBox(height: 10),
                // Likes ❤️ + Gifts 🎁 — directly on the Discover card
                // (no extra query, no null crash).
                _buildCardStatsRow(profile),
                const SizedBox(height: 20),
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
                              borderRadius: AppRadius.xl,
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
                      // MATCH button — HII ndiyo njia pekee ya kupendana:
                      // inarekodi like halisi kwenye Supabase na kuunda
                      // match kama pande zote mbili zimependana.
                      // (Swipe ni scroll tu — hairiasi kupendana.)
                      Column(
                        children: [
                          GestureDetector(
                            onTap: () => _likeProfile(profile),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.favorite_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Match",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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

  /// Likes ❤️ + Gifts 🎁 row on the Discover card.
  /// Safe against null/missing keys (old schema has no counters).
  /// Strip ndogo ya picha juu ya card (Tinder-style): sehemu zote za picha,
  /// zilizopo zimejaa, zilizobaki ni transparent. Inaonyesha picha iliyopo.
  Widget _photoStrip({required int count, required int index}) {
    return Row(
      children: List.generate(count, (i) {
        final bool active = i == index;
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCardStatsRow(Map<String, dynamic> profile) {
    final int likes = (profile['likesCount'] as num?)?.toInt() ?? 0;
    final int gifts = (profile['giftsCount'] as num?)?.toInt() ?? 0;

    Widget pill({required IconData icon, required String text}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: AppRadius.card,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        pill(icon: Icons.favorite_rounded, text: '$likes'),
        pill(icon: Icons.card_giftcard_rounded, text: '$gifts'),
      ],
    );
  }
}