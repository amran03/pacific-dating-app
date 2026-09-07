import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_color.dart';
import '../data/user_model.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/welcome_screen.dart';

import 'screens/profile_setting.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/buy_coins_screen.dart';
import 'screens/badge_store_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/profile_image_with_ring.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingPhoto = false;

  Future<void> _changeProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');

      await ref.putFile(File(picked.path));
      final String downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'profileImageUrl': downloadUrl,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Picha ya profile imebadilishwa!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imeshindikana kupakia picha: $e")),
        );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Je, una hakika unataka kutoka kwenye akaunti yako?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Ghairi", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop(); // funga dialog
              await FirebaseAuth.instance.signOut();
              // Tunaelekeza moja kwa moja kwenda WelcomeScreen na kufuta
              // stack YOTE ya nyuma - hii inahakikisha logout inafanya
              // kazi hata kama AuthGate haipo tena kwenye navigation
              // stack (mfano baada ya PacificLaunchScreen kuondoa route
              // za nyuma zote kwa pushAndRemoveUntil wakati wa usajili).
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, elevation: 0),
            child: const Text("Toka", style: TextStyle(color: Colors.white)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Account", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
        content: const Text("Onyo! Kitendo hiki kitafuta kabisa akaunti yako na taarifa zote. Huwezi kuzirejesha tena."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Ghairi", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => _handleDeleteAccount(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, elevation: 0),
            child: const Text("Futa Kabisa", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop(); // funga dialog ya onyo
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();
      // Elekeza moja kwa moja WelcomeScreen - AuthGate huenda haipo tena
      // kwenye stack (angalia maelezo kwenye Logout hapo juu).
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (context.mounted) _showReauthDialog(context, user);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imeshindikana kufuta akaunti: ${e.message}")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Kosa: $e")));
      }
    }
  }

  // Kwa usalama, Firebase wakati mwingine inahitaji uthibitishe upya password
  // yako kabla ya kufuta akaunti (hasa kama umeshalogin muda mrefu uliopita).
  void _showReauthDialog(BuildContext context, User user) {
    final TextEditingController passwordController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Thibitisha Password", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Kwa usalama, weka password yako tena kabla ya kufuta akaunti."),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(hintText: "Password", border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Ghairi", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                if (user.email == null) return;
                setDialogState(() => isSubmitting = true);
                try {
                  final credential = EmailAuthProvider.credential(
                    email: user.email!,
                    password: passwordController.text.trim(),
                  );
                  await user.reauthenticateWithCredential(credential);
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                  await user.delete();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                          (route) => false,
                    );
                  }
                } catch (e) {
                  setDialogState(() => isSubmitting = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Password si sahihi. Jaribu tena.")),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, elevation: 0),
              child: isSubmitting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text("Thibitisha na Futa", style: TextStyle(color: Colors.white)),
            ),
          ],
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
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.12),
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
                color: Colors.pinkAccent.withOpacity(0.08),
              ),
            ),
          ),

          // Main Content
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser == null
                ? null
                : FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              UserModel? me;
              if (snapshot.hasData && snapshot.data!.exists) {
                me = UserModel.fromMap(snapshot.data!.data() as Map<String, dynamic>);
              }

              final String displayName = me != null ? "${me.name}, ${me.age}" : "Mtumiaji";
              final String displayLocation = (me?.location != null && me!.location!.isNotEmpty)
                  ? me.location!
                  : "Tanzania";
              final String photoUrl = (me?.profileImageUrl != null && me!.profileImageUrl!.isNotEmpty)
                  ? me.profileImageUrl!
                  : 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?q=80&w=300&auto=format&fit=crop';
              final int coinBalance = me?.coins ?? 0;

              return
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // Glassmorphism App Bar
                    SliverAppBar(
                      floating: true,
                      pinned: true,
                      backgroundColor: Colors.white.withOpacity(0.7),
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      flexibleSpace: ClipRRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(color: Colors.white.withOpacity(0.5)),
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
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
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
                                          color: AppColors.primary.withOpacity(0.3),
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
                                                color: Colors.black.withOpacity(0.4),
                                              ),
                                              child: const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
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
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            "Active Status: Online",
                                            style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
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
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 36),
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
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    child: const Text(
                                      "Top Up",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // --- 2. PROFILE SETTINGS & OPTIONS ---
                            _buildMenuSection(
                              title: "Account & Preferences",
                              items: [
                                _buildMenuItem(
                                  icon: Icons.tune_rounded,
                                  color: Colors.deepPurple,
                                  title: _lang.t('App Settings', sw: 'Mipangilio ya App'),
                                  subtitle: _lang.t('Language, Dark Mode, Privacy & more', sw: 'Lugha, Mode Nyeusi, Faragha na zaidi'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      FadeSlideRoute(page: const SettingsScreen()),
                                    );
                                  },
                                ),
                                _buildMenuItem(
                                  icon: Icons.settings_rounded,
                                  color: Colors.blue,
                                  title: "Profile Settings",
                                  subtitle: "Badili taarifa zako, picha na mapendeleo",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      // Hapa lazima iwe jina sahihi la class iliyopo kwenye "profile_setting.dart"
                                      MaterialPageRoute(builder: (context) => const ProfileSettingsScreen()),
                                    ).then((_) {
                                      setState(() {});
                                    });
                                  },
                                ),
                                _buildMenuItem(
                                  icon: Icons.tune_rounded,
                                  color: Colors.teal,
                                  title: "App Settings",
                                  subtitle: "Lugha, Mwangaza, Arifa, Na Matakazo",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                                    );
                                  },
                                ),
                                _buildMenuItem(
                                  icon: Icons.workspace_premium_rounded,
                                  color: AppColors.coinGold,
                                  title: "VIP Badges",
                                  subtitle: "Nunua Bronze, Gold au Diamond badge",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const BadgeStoreScreen(),),
                                    ).then((_) {
                                      setState(() {});
                                    });
                                  },
                                ),
                                _buildMenuItem(
                                  icon: Icons.privacy_tip_rounded,
                                  color: Colors.purple,
                                  title: "Privacy Policy",
                                  subtitle: "Soma sheria na jinsi tunavyolinda taarifa zako",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 3. ACTIONS (LOGOUT & DELETE ACCOUNT) ---
                            _buildMenuSection(
                              title: "Security & Danger Zone",
                              items: [
                                _buildMenuItem(
                                  icon: Icons.logout_rounded,
                                  color: Colors.orange,
                                  title: "Logout",
                                  subtitle: "Toka kwenye akaunti yako kwa sasa",
                                  onTap: () => _showLogoutDialog(context),
                                ),
                                _buildMenuItem(
                                  icon: Icons.delete_forever_rounded,
                                  color: Colors.red,
                                  title: "Delete Account",
                                  subtitle: "Futa kabisa akaunti na data zako zote",
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
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
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
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
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