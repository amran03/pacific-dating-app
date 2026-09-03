import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/chat/domain/models/chat_model.dart';
import 'package:pacific_dating_app/features/chat/presentation/individual_chat_screen.dart';

/// Inaonyesha profile KAMILI ya mtumiaji MWINGINE (sio ya mwenyewe).
/// Inafunguliwa kutoka Discover card, Likes grid, au Chat header.
/// Ni real-time - kama huyo mtumiaji akibadilisha bio/picha yake,
/// itasasika hapa papo hapo bila kufunga na kufungua tena.
class PublicProfileScreen extends StatelessWidget {
  final String uid;

  const PublicProfileScreen({super.key, required this.uid});

  Future<void> _openChat(BuildContext context, UserModel user) async {
    final matchmakingService = MatchmakingService();

    // Onyesha kiashiria kidogo cha "kukagua" wakati tunasoma bei/access
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
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

    final bool alreadyUnlocked = accessInfo['unlocked'] as bool;
    final int price = accessInfo['price'] as int;

    // Tayari imefunguliwa AU ni bure kabisa - endelea moja kwa moja
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
        title: const Text("Fungua Mazungumzo 🔒"),
        content: Text(
          "${user.name} anahitaji Coins $price kufungua mazungumzo naye kwa mara ya kwanza. Baada ya hapo mtaweza kuongea bila malipo tena.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Ghairi", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text("Lipa 🪙 $price", style: const TextStyle(color: Colors.white)),
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
                  ? "Huna Coins za kutosha. Nenda Profile -> Top Up."
                  : "Imeshindikana kufungua chat: $e",
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
                : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=600',
            lastMessage: '',
            timeSent: '',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
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

          final user = UserModel.fromMap(snapshot.data!.data() as Map<String, dynamic>);
          final String imageUrl = (user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
              ? user.profileImageUrl!
              : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=800';

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
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(color: Colors.grey.shade400),
                      ),
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
                                fontWeight: FontWeight.w900,
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
                      if (user.bio != null && user.bio!.isNotEmpty) ...[
                        const Text("Kuhusu Yangu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        const Text("Mapendeleo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                                "Kufungua chat: 🪙 ${user.chatUnlockPrice} Coins (mara moja tu)",
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
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
          Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}