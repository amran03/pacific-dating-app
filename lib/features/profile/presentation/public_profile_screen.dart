import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';
import 'package:pacific_dating_app/features/profile/presentation/widgets/profile_image_with_ring.dart';
import 'package:pacific_dating_app/features/chat/presentation/individual_chat_screen.dart';
import 'package:pacific_dating_app/core/widgets/heart_loader.dart';

/// Inaonyesha profile KAMILI ya mtumiaji MWINGINE (sio ya mwenyewe).
/// Inafunguliwa kutoka Discover card, Likes grid, au Chat header.
/// Ni real-time - kama huyo mtumiaji akibadilisha bio/picha yake,
/// itasasika hapa papo hapo bila kufunga na kufungua tena.
///
/// Sehemu ya juu ya profile inaonyesha pia:
///  - idadi ya Likes alizopokea (❤️)
///  - zawadi kubwa (top gifts to thamani) alizopokea (🎁)
///  - rating ya nyota (⭐ wastani + idadi ya wapimaji, na nyota 5 za kupima)
class PublicProfileScreen extends StatefulWidget {
  final String uid;

  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _topGifts = [];
  bool _ratingBusy = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final svc = MatchmakingService();
      final stats = await svc.fetchUserStats(widget.uid);
      final top = await svc.fetchTopGiftsReceived(widget.uid, limit: 3);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _topGifts = top;
      });
    } catch (_) {}
  }

  Future<void> _rate(int stars) async {
    if (_ratingBusy) return;
    setState(() => _ratingBusy = true);
    try {
      await MatchmakingService().rateUser(widget.uid, stars);
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You gave $stars! ⭐')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send rating. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  Future<void> _openChat(BuildContext context, UserModel user) async {
    final matchmakingService = MatchmakingService();

    // Onyesha kiashiria kidogo cha "kukagua" wakati tunasoma bei/access
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: HeartLoader(size: 52),
      ),
    );

    Map<String, dynamic> accessInfo;
    try {
      accessInfo = await matchmakingService.getChatAccessInfo(user.uid);
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // funga loading
      return;
    }

    if (context.mounted) Navigator.pop(context); // funga loading
    if (!context.mounted) return;

    final bool alreadyUnlocked = (accessInfo['unlocked'] as bool?) ?? true;
    final int price = (accessInfo['price'] as num?)?.toInt() ?? 0;

    // Tayari imefunguliwa AU ni bure kabisa - endelea moja to moja
    if (alreadyUnlocked || price <= 0) {
      if (!alreadyUnlocked) {
        try {
          await matchmakingService.payAndUnlockChat(user.uid);
        } catch (_) {
          // hata ikishindikana kimya, bado ruhusu kuona ujumbe (fallback salama)
        }
      }
      if (context.mounted) _navigateToChat(context, user);
      return;
    }

    // Ina bei - muulize kwanza kabla ya kutoa coins
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Unlock Chat"),
        content: Text(
          "${user.name} requires $price Coins to open a chat with you for the first time. After that you can chat for free.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text("Pay $price", style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await matchmakingService.payAndUnlockChat(user.uid);
      if (context.mounted) _navigateToChat(context, user);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('INSUFFICIENT_COINS')
                  ? "You do not have enough Coins. Go to Profile -> Top Up."
                  : "Failed to open chat: $e",
            ),
          ),
        );
      }
    }
  }

  void _navigateToChat(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IndividualChatScreen(
          chat: ChatModel(
            id: user.uid,
            name: user.name,
            avatarUrl: (user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
                ? user.profileImageUrl!
                : '',
            lastMessage: '',
            timeSent: '',
          ),
        ),
      ),
    );
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'diamond':
        return const Color(0xFFB9F2FF);
      default:
        return Colors.transparent;
    }
  }

  /// Real avatar fallback: initials on a gradient, used when the user
  /// has no profile photo (or the photo URL is broken).
  Widget _initialsHeader(String name) {
    return Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 110,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('users')
            .stream(primaryKey: ['uid'])
            .eq('uid', widget.uid)
            .limit(1),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: HeartLoader(size: 62));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Expanded(
                    child: Center(child: Text("Profile hii haipatikani tena.")),
                  ),
                ],
              ),
            );
          }

          final user = UserModel.fromMap(snapshot.data!.first);
          final String imageUrl = (user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
              ? user.profileImageUrl!
              : '';

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Picha kubwa juu, na jina limewekwa juu yake
              SliverAppBar(
                expandedHeight: 420,
                pinned: true,
                backgroundColor: AppColors.primary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl.isNotEmpty)
                        Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _initialsHeader(user.name),
                        )
                      else
                        _initialsHeader(user.name),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.5, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 120,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ProfileImageWithRing(
                            imageUrl: imageUrl,
                            badgeTier: user.badgeTier,
                            size: 120,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${user.name}, ${user.age}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (user.badgeTier != 'none')
                              Container(
                                margin: const EdgeInsets.only(left: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getTierColor(user.badgeTier),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  user.badgeTier.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (user.location != null && user.location!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: Colors.white70, size: 16),
                                    const SizedBox(width: 4),
                                    Text(user.location!, style: const TextStyle(color: Colors.white70)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---- STATS: Likes + Gifts + Rating (sehemu ya profile) ----
                      _buildStatsCard(user),
                      const SizedBox(height: 20),
                      if (user.bio != null && user.bio!.isNotEmpty) ...[
                        const Text("About Me", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(user.bio!, style: const TextStyle(color: Colors.black87, height: 1.5)),
                        const SizedBox(height: 24),
                      ],

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (user.gender != null && user.gender!.isNotEmpty)
                            _buildInfoChip(Icons.person_rounded, user.gender!),
                          if (user.relationshipGoal != null && user.relationshipGoal!.isNotEmpty)
                            _buildInfoChip(Icons.favorite_rounded, user.relationshipGoal!),
                          if (user.interestedGender != null && user.interestedGender!.isNotEmpty)
                            _buildInfoChip(Icons.search_rounded, "Anatafuta ${user.interestedGender}"),
                          if (user.heightCm != null)
                            _buildInfoChip(Icons.height_rounded, "${user.heightCm} cm"),
                          if (user.education != null && user.education!.isNotEmpty)
                            _buildInfoChip(Icons.school_rounded, user.education!),
                          if (user.occupation != null && user.occupation!.isNotEmpty)
                            _buildInfoChip(Icons.work_rounded, user.occupation!),
                          if (user.smokingHabit != null && user.smokingHabit!.isNotEmpty)
                            _buildInfoChip(Icons.smoking_rooms_rounded, "Sigara: ${user.smokingHabit}"),
                          if (user.drinkingHabit != null && user.drinkingHabit!.isNotEmpty)
                            _buildInfoChip(Icons.local_bar_rounded, "Pombe: ${user.drinkingHabit}"),
                        ],
                      ),

                      if (user.interests.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text("Mapendeleo", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: user.interests
                              .map((interest) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(interest, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ))
                              .toList(),
                        ),
                      ],

                      const SizedBox(height: 32),

                      if (user.chatUnlockPrice > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline_rounded, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(
                                "Kufungua chat: ${user.chatUnlockPrice} Coins (mara moja tu)",
                                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () => _openChat(context, user),
                          icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                          label: Text(
                            user.chatUnlockPrice > 0 ? "Tuma Ujumbe (🪙 ${user.chatUnlockPrice})" : "Tuma Ujumbe",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _statTile(
      {required IconData icon,
      required Color color,
      required String value,
      required String label}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17)),
        Text(label,
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildStarsRow(int myStars) {
    return Row(
      children: [
        const Text('Mpe rating:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(width: 8),
        ...List.generate(5, (i) {
          final star = i + 1;
          final filled = star <= myStars;
          return InkWell(
            onTap: _ratingBusy ? null : () => _rate(star),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: const Color(0xFFFFB800),
                size: 30,
              ),
            ),
          );
        }),
        if (_ratingBusy) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }

  /// Kadi ya takwimu: Likes | Gifts (kubwa 3) | Rating + nyota za kupima.
  Widget _buildStatsCard(UserModel user) {
    final int likes = user.likesReceivedCount > 0
        ? user.likesReceivedCount
        : ((_stats?['likes'] as int?) ?? 0);
    final int giftsCount = user.giftsReceivedCount > 0
        ? user.giftsReceivedCount
        : ((_stats?['giftsCount'] as int?) ?? 0);
    final int giftsValue = user.giftsReceivedValue > 0
        ? user.giftsReceivedValue
        : ((_stats?['giftsValue'] as int?) ?? 0);
    double avg = user.averageRating;
    int rCount = user.ratingCount;
    if (rCount == 0 && _stats != null) {
      avg = (_stats!['avgRating'] as num?)?.toDouble() ?? 0;
      rCount = (_stats!['ratingCount'] as int?) ?? 0;
    }
    final int myStars = (_stats?['myStars'] as int?) ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _statTile(
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFFF4B6E),
                  value: '$likes',
                  label: 'Likes',
                ),
              ),
              Container(width: 1, height: 44, color: Colors.grey.shade200),
              Expanded(
                child: _statTile(
                  icon: Icons.card_giftcard_rounded,
                  color: const Color(0xFFFFB800),
                  value: '$giftsCount',
                  label: giftsValue > 0 ? 'Gifts (🪙 $giftsValue)' : 'Gifts',
                ),
              ),
              Container(width: 1, height: 44, color: Colors.grey.shade200),
              Expanded(
                child: _statTile(
                  icon: Icons.star_rounded,
                  color: const Color(0xFFFFB800),
                  value: rCount > 0 ? avg.toStringAsFixed(1) : '—',
                  label: rCount > 0 ? 'Rating ($rCount)' : 'Rating',
                ),
              ),
            ],
          ),
          if (_topGifts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Top gifts received',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _topGifts.map((g) {
                final String emoji =
                    (g['gift_emoji']?.toString().isNotEmpty ?? false)
                        ? g['gift_emoji'].toString()
                        : '🎁';
                final String name =
                    (g['gift_name']?.toString().isNotEmpty ?? false)
                        ? g['gift_name'].toString()
                        : 'Gifts';
                final int cost =
                    ((g['coin_cost'] as num?)?.toInt() ?? 0);
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFFB800)
                            .withValues(alpha: 0.35)),
                  ),
                  child: Text('$emoji $name • 🪙 $cost',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _buildStarsRow(myStars),
        ],
      ),
    );
  }
}