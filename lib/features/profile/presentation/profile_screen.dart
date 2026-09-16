import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_color.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/user_prefs.dart';
import '../../../core/widgets/heart_loader.dart';
import '../data/user_model.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/welcome_screen.dart';

import 'screens/edit_profile_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/buy_coins_screen.dart';
import 'screens/badge_store_screen.dart';
import 'widgets/profile_image_with_ring.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile photo updated!"), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to upload photo: $e")),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
                                borderRadius: BorderRadius.circular(24),
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
                                            borderRadius: BorderRadius.circular(10),
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
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withValues(alpha: 0.2),
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

                            // --- 2. NOTIFICATIONS ---
                            _buildMenuSection(
                              title: "Notifications",
                              items: [
                                _buildSwitchTile(
                                  icon: Icons.notifications_active_rounded,
                                  color: Colors.teal,
                                  title: "Arifa (Notifications)",
                                  subtitle: "Pokaa arifa za matches, messages na gifts",
                                  value: me?.notificationsEnabled ?? false,
                                  onChanged: (v) => _toggleNotifications(v),
                                ),
                                _buildSwitchTile(
                                  icon: Icons.vibration_rounded,
                                  color: Colors.deepOrange,
                                  title: "Mtikisiko (Vibration)",
                                  subtitle: "Simu iteteme inapofika arifa mpya",
                                  value: me?.vibrationEnabled ?? true,
                                  onChanged: (v) =>
                                      _saveBoolPref('vibration_enabled', v),
                                ),
                                _buildSwitchTile(
                                  icon: Icons.volume_up_rounded,
                                  color: Colors.pink,
                                  title: "Sauti ya Arifa",
                                  subtitle: "Sikia sauti inapofika arifa mpya",
                                  value: me?.soundEnabled ?? true,
                                  onChanged: (v) =>
                                      _saveBoolPref('sound_enabled', v),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 3. CHAT PREFERENCES ---
                            _buildMenuSection(
                              title: "Chat Preferences",
                              items: [
                                _buildSwitchTile(
                                  icon: Icons.done_all_rounded,
                                  color: Colors.green,
                                  title: "Read Receipts (Seen Ticks)",
                                  subtitle: "Mwenzako aone ujumbe wake umeusoma",
                                  value: me?.readReceiptsEnabled ?? true,
                                  onChanged: (v) => _saveBoolPref(
                                    'read_receipts_enabled',
                                    v,
                                  ),
                                ),
                                _buildSwitchTile(
                                  icon: Icons.keyboard_alt_outlined,
                                  color: Colors.blueGrey,
                                  title: "Typing Indicator",
                                  subtitle: "Mwenzako aone unaandika ujumbe",
                                  value: me?.typingIndicatorEnabled ?? true,
                                  onChanged: (v) => _saveBoolPref(
                                    'typing_indicator_enabled',
                                    v,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 4. CHAT LOCK (COINS) ---
                            _buildMenuSection(
                              title: "Chat Lock (Coins)",
                              items: [
                                _buildSwitchTile(
                                  icon: Icons.lock_rounded,
                                  color: AppColors.coinGold,
                                  title: "Funga Chat to Coins",
                                  subtitle: me != null && me.chatUnlockPrice > 0
                                      ? 'Chat yako imefungwa — wengine wanalipa '
                                          '${me.chatUnlockPrice} Coins kufungua mara moja tu'
                                      : 'Chat yako ni BURE to kila mtu',
                                  value: (me?.chatUnlockPrice ?? 0) > 0,
                                  onChanged: (v) {
                                    if (v) {
                                      _showUnlockPriceDialog(
                                        context,
                                        me?.chatUnlockPrice ?? 0,
                                      );
                                    } else {
                                      _showUnlockPriceDialog(context, 0);
                                    }
                                  },
                                ),
                                _buildMenuItem(
                                  icon: Icons.monetization_on_rounded,
                                  color: AppColors.coinGold,
                                  title: "Change Unlock Price",
                                  subtitle: me != null && me.chatUnlockPrice > 0
                                      ? "Current price: ${me.chatUnlockPrice} Coins"
                                      : "Set your coin price for locking chat",
                                  onTap: () =>
                                      _showUnlockPriceDialog(context, me?.chatUnlockPrice ?? 0),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // --- 5. PRIVACY & VISIBILITY ---
                            _buildMenuSection(
                              title: "Privacy & Visibility",
                              items: [
                                _buildSwitchTile(
                                  icon: Icons.visibility_rounded,
                                  color: Colors.deepPurple,
                                  title: "Show Online Status",
                                  subtitle: "Let others see when you are online or last seen",
                                  value: me?.showOnlineStatusEnabled ?? true,
                                  onChanged: (v) => _saveBoolPref(
                                    'show_online_status_enabled',
                                    v,
                                  ),
                                ),
                                _buildSwitchTile(
                                  icon: Icons.explore_rounded,
                                  color: Colors.orange,
                                  title: "Show in Discover",
                                  subtitle: "Let new people see you on swipe cards",
                                  value: me?.discoverable ?? true,
                                  onChanged: (v) => _saveBoolPref('discoverable', v),
                                ),
                                _buildSwitchTile(
                                  icon: Icons.location_on_rounded,
                                  color: Colors.indigo,
                                  title: "Show Distance (Location)",
                                  subtitle: "Let nearby people find you on Discover",
                                  value: me?.locationEnabled ?? false,
                                  onChanged: (v) => _toggleLocation(v),
                                ),
                                _buildMenuItem(
                                  icon: Icons.privacy_tip_rounded,
                                  color: Colors.purple,
                                  title: "Privacy Policy",
                                  subtitle: "Read the rules and how we protect your data",
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

                            // --- 6. PREMIUM & WALLET ---
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

                            // --- 7. ACCOUNT ---
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

                            // --- 8. ACTIONS (LOGOUT & DELETE ACCOUNT) ---
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
  // PROFILE SETTINGS — SWITCHES & CHAT UNLOCK PRICE
  // ============================================================

  /// Switch ya Arifa: inahifadhi DB NA ku-update NotificationService
  /// ya papo hapo (bila kusubiri app ifungwe upya).
  Future<void> _toggleNotifications(bool enabled) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    NotificationService.instance.setUserEnabled(enabled);
    try {
      await Supabase.instance.client.from('users').update({
        'notifications_enabled': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Switch ya Location: inahifadhi users.location_enabled (Discover
  /// inaitumia kuonyesha umbali wa watu walio karibu).
  Future<void> _toggleLocation(bool enabled) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('users').update({
        'location_enabled': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
/// Switch ya jumla: inahifadhi mapendeleo ya boolean kwenye users
  /// (read_receipts_enabled, typing_indicator_enabled, discoverable, n.k.).
  /// Inatumika na Profile Settings zote zenye switch.
  Future<void> _saveBoolPref(String column, bool value) async {
    // Cache ya papo hapo — chat/presence zinaona mabadiliko bila restart.
    UserPrefs.instance.set(column, value);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('users').update({
        column: value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', user.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Dialog ya kuweka bei (coins) ya kufungua chat na wewe — 0 = bure,
  /// 500 = bei ya juu kabisa. Payout inaenda moja to moja kwenye wallet
  /// yako mtu akilipa, na unlock ni YA MILELE to anayelipa.
  Future<void> _showUnlockPriceDialog(BuildContext context, int currentPrice) async {
    int selected = currentPrice.clamp(0, 500);
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Bei ya Kufungua Chat", style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Weki bei ya Pasific Coins ambayo mtu mwingine atalipa kufungua mazungumzo nawe. Malipo hayo yanakuingia kwenye wallet yako.",
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              Text(
                "$selected Coins",
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.coinGold,
                ),
              ),
              Slider(
                value: selected.toDouble(),
                min: 0,
                max: 500,
                divisions: 25,
                activeColor: AppColors.primary,
                label: "$selected",
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Text(
                selected == 0 ? "Bure — chat inafunguka moja to moja" : "Unalipwa mara mtu anapofungua",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                // Tunachukua messenger KABLA ya await — ili tusitumie
                // BuildContext baada ya async gap (salama to State dispose).
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);
                try {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) return;
                  await Supabase.instance.client.from('users').update({
                    'chat_unlock_price': selected,
                    'updated_at': DateTime.now().toIso8601String(),
                  }).eq('uid', user.id);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text("Bei imewekwa: $selected Coins to kufungua chat!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.redAccent),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, elevation: 0),
              child: const Text("Hifadhi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
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
            borderRadius: BorderRadius.circular(22),
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
        borderRadius: BorderRadius.circular(22),
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

  // Widget ya switch (ON/OFF) — inatumika kwenye settings za arifa,
  // location n.k. Mtindo uleule wa menu items ila na Switch badala ya arrow.
  Widget _buildSwitchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Switch.adaptive(
                value: value,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.primary,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}