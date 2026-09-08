import 'package:flutter/material.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/matchmaking_service.dart';
import 'package:pacific_dating_app/features/profile/data/user_model.dart';
import 'package:pacific_dating_app/features/profile/presentation/public_profile_screen.dart';

class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key});

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen> {
  final MatchmakingService _matchmakingService = MatchmakingService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "Likes Center",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: _matchmakingService.streamUsersWhoLikedMe(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (snapshot.hasError) {
            // Kama unaona error hapa mara ya kwanza, mara nyingi ni kwa
            // sababu Firestore Composite Index bado haijajengwa. Angalia
            // 'debug console' - Firebase hutoa LINK ya moja kwa moja ya
            // kujenga index hiyo, bonyeza tu link hiyo.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Imeshindikana kupakua Likes: ${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            );
          }

          final likedByUsers = snapshot.data ?? [];

          if (likedByUsers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite_border_rounded, size: 70, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "Bado hakuna aliyekupenda",
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Endelea kutafuta kwenye Discover - watu wanaokupenda\nwataonekana hapa moja kwa moja.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w300),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${likedByUsers.length} Watu wamekupenda",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: likedByUsers.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.75,
                    ),
                    itemBuilder: (context, index) {
                      final user = likedByUsers[index];
                      // Real photo from Supabase; initials fallback when empty.
                      final String imageUrl =
                          (user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
                              ? user.profileImageUrl!
                              : '';

                      return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PublicProfileScreen(uid: user.uid),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: imageUrl.isNotEmpty
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              Container(color: Colors.grey.shade300),
                                        )
                                      : Container(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          alignment: Alignment.center,
                                          child: Text(
                                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                            style: const TextStyle(
                                              fontSize: 42,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 12,
                                  right: 12,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${user.name}, ${user.age}",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ));
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}