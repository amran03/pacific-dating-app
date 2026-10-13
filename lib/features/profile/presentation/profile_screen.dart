import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_color.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/heart_loader.dart';
import '../data/user_model.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/welcome_screen.dart';

import 'screens/edit_profile_screen.dart';
import 'screens/buy_coins_screen.dart';
import 'screens/badge_store_screen.dart';
import 'screens/app_settings_screen.dart';
import '../../../services/pesapal_service.dart';
import 'widgets/profile_image_with_ring.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingPhoto = false;

  Future<void> _changeProfilePhoto() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final storageService = StorageService();
      final downloadUrl = await storageService.uploadProfileImage(user.id, File(picked.path));

      if (downloadUrl != null) {
        await Supabase.instance.client.from('users').update({
          'profile_image_url': downloadUrl,
        }).eq('uid', user.id);

        if (mounted) {
          showAppNotification(context, "Profile photo updated!", color: Colors.green);
        }
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, "Failed to upload photo: $e");
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  // Dialog ya Logout
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to log out of your account?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop(); // funga dialog
              await Supabase.instance.client.auth.signOut();
              // Tunaelekeza moja to moja kwenda WelcomeScreen na kufuta
              // stack YOTE ya nyuma
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, elevation: 0),
            child: const Text("Log Out", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Dialog ya Delete Account
  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        title: const Text("Delete Account", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
        content: const Text("Warning! This will permanently delete your account and all data. You cannot undo this."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => _handleDeleteAccount(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, elevation: 0),
            child: const Text("Delete Permanently", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop(); // funga dialog ya onyo
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Futa taarifa za profile kwanza
      await Supabase.instance.client.from('users').delete().eq('uid', user.id);
      
      // Supabase Auth deletion mara nyingi hufanywa upande wa server.
      // Hapa tutamsign-out mtumiaji na kumrudisha welcome screen.
      await Supabase.instance.client.auth.signOut();
      
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (route) => false,
      );
    } catch (e) {
      if (context.mounted) {
        showAppNotification(context, "Error: $e");
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
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
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.pinkAccent.withValues(alpha: 0.08),
              ),
            ),
          ),

          // Main Content
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.auth.currentUser == null
                ? const Stream.empty()
                : Supabase.instance.client
                .from('users')
                .stream(primaryKey: ['uid'])
                .eq('uid', Supabase.instance.client.auth.currentUser!.id)
                .limit(1),
            builder: (context, snapshot) {
              UserModel? me;
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                me = UserModel.fromMap(snapshot.data!.first);
              }

              // Loading ya kisasa: moyo unaodunda wakati profile inapakiwa.
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: HeartLoader(size: 68));
              }

              final String displayName = me != null ? "${me.name}, ${me.age}" : "User";
              final String displayLocation = (me?.location != null && me!.location!.isNotEmpty)
                  ? me.location!
                  : "Tanzania";
              // Real profile photo from Supabase (empty string -> initials/avatar fallback).
              final String photoUrl = (me?.profileImageUrl != null && me!.profileImageUrl!.isNotEmpty)
                  ? me.profileImageUrl!
                  : '';
              final int coinBalance = me?.coins ?? 0;
              // Real online status from presence data (not hardcoded).
              final bool isOnline = (me?.isOnline ?? false);

              return
                CustomScrollView(
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
                        "My Profile",
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      centerTitle: true,
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // --- PROFILE HEADER & CARD ---
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.85),
                                borderRadius: AppRadius.xl,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [AppColors.primary, Colors.pinkAccent],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: GestureDetector(
                                      onTap: _isUploadingPhoto ? null : _changeProfilePhoto,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          ProfileImageWithRing(
                                            imageUrl: photoUrl,
                                            badgeTier: me?.badgeTier ?? 'none',
                                            size: 70,
                                          ),
                                          if (_isUploadingPhoto)
                                            Container(
                                              width: 70,
                                              height: 70,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.black.withValues(alpha: 0.45),
                                              ),
                                              // Loading ya kisasa: moyo unaodunda
                                              child: const HeartLoader(size: 36, color: Colors.white),
                                            )
                                          else
                                            Positioned(
                                              bottom: 0,
                                              right: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 1.5),
                                                ),
                                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 12),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Hapa zinasoma data kutoka Firestore (real-time)
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          displayLocation,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isOnline
                                                ? Colors.green.withValues(alpha: 0.1)
                                                : Colors.grey.withValues(alpha: 0.15),
                                            borderRadius: AppRadius.sm,
                                          ),
                                          child: Text(
                                            isOnline ? "Active Status: Online" : "Offline",
                                            style: TextStyle(
                                              color: isOnline ? Colors.green : Colors.grey.shade600,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // --- 1. COIN BALANCE SECTION ---
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFF3CD), Color(0xFFFFE8A1)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: AppRadius.card,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.monetization_on_rounded, color: AppColors.coinGoldDark, size: 36),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Pacific Coins",
                                            style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "$coinBalance Coins",
                                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => const BuyCoinsScreen()),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.coinGold,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: AppRadius.sm),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    child: const Text(
                                      "Top Up",
                                      // White kwenye gold-bg haisomeki
                                      // (contrast ~1.6:1) â€” tumia brown nzito.
                                      style: TextStyle(
                                        color: Color(0xFF5F4500),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                ),
                                  const SizedBox(height: 14),

                                  // --- COIN PACKAGES (preview) ---
                                  // Vifurushi vya kununua coins (100/500/1000)
                                  // na bei zake (1 Coin = TSh 25 kwa PesaPal).
                                  // Gusa kifurushi -> BuyCoinsScreen (malipo
                                  // kamili ya PesaPal + orodha ya vifurushi vyote).
                                  Row(
                                    children: [
                                      const Text(
                                        "Coin Packages",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => const BuyCoinsScreen()),
                                          );
                                        },
                                        child: const Text(
                                          "View all",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryDeep,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _coinPackageChip(context, 100),
                                      const SizedBox(width: 8),
                                      _coinPackageChip(context, 500),
                                      const SizedBox(width: 8),
                                      _coinPackageChip(context, 1000),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // --- 2. SETTINGS (inayojitegemea) ---
                            // Notifications, Chat Preferences,
                            // Chat Lock na Privacy & Visibility
                            // zote ziko kwenye AppSettingsScreen.
                            _buildMenuSection(
                              title: "Settings",
                              items: [
                                _buildMenuItem(
                                  icon: Icons.settings_rounded,
                                  color: AppColors.primary,
                                  title: "Settings",
                                  subtitle:
                                      "Notifications, Chat, Chat Lock & Privacy",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const AppSettingsScreen()),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 3. PREMIUM & WALLET ---
                            _buildMenuSection(
                              title: "Premium & Wallet",
                              items: [
                                _buildMenuItem(
                                  icon: Icons.workspace_premium_rounded,
                                  color: AppColors.coinGold,
                                  title: "VIP Badges",
                                  subtitle: "Buy a Bronze, Gold or Diamond badge",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const BadgeStoreScreen(),),
                                    ).then((_) {
                                      setState(() {});
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 4. ACCOUNT ---
                            _buildMenuSection(
                              title: "Account",
                              items: [
                                _buildMenuItem(
                                  icon: Icons.edit_rounded,
                                  color: Colors.blue,
                                  title: "Edit Profile",
                                  subtitle: "Badili taarifa zako, picha na mapendeleo",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                                    ).then((_) {
                                      setState(() {});
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 5. ACTIONS (LOGOUT & DELETE ACCOUNT) ---
                            _buildMenuSection(
                              title: "Security & Danger Zone",
                              items: [
                                _buildMenuItem(
                                  icon: Icons.logout_rounded,
                                  color: Colors.orange,
                                  title: "Logout",
                                  subtitle: "Log out of your account now",
                                  onTap: () => _showLogoutDialog(context),
                                ),
                                _buildMenuItem(
                                  icon: Icons.delete_forever_rounded,
                                  color: Colors.red,
                                  title: "Delete Account",
                                  subtitle: "Permanently delete your account and all your data",
                                  onTap: () => _showDeleteAccountDialog(context),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROFILE SETTINGS â€” SWITCHES & CHAT UNLOCK PRICE
  // ============================================================

  /// Chip ndogo ya kifurushi cha coins kwenye wallet card.
  /// Inaonyesha idadi ya coins na bei yake (1 Coin = TSh 25 â€” PesaPal).
  /// Gusa -> BuyCoinsScreen (malipo kamili ya PesaPal).
  Widget _coinPackageChip(BuildContext context, int coins) {
    final int price = coins * PesapalService.kCoinRateTzs;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BuyCoinsScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.65),
            borderRadius: AppRadius.sm,
            border: Border.all(
              color: AppColors.coinGoldDark.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Text(
                "\u{1FA99} $coins",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF5F4500),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "TSh $price",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // Widget ya kutengeneza makundi ya menyu
  Widget _buildMenuSection({required String title, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black54),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: AppRadius.card,
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  // Widget ya kila kipengele kimoja ndani ya menyu
  Widget _buildMenuItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

}
