import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_color.dart';
import '../../../../core/localization/app_language.dart';
import '../../../../core/localization/app_theme.dart';
import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';

/// Smooth slide+fade route used for legal pages (nice, quick transition).
class FadeSlideRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeSlideRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _showOnlineStatus = true;
  FocusNode? _notificationFocusNode;

  AppLanguage get _lang => AppLanguage.instance;
  AppTheme get _theme => AppTheme.instance;

  // Language picker — English au Swahili, mpaka app nzima.
  void _showLanguagePicker(BuildContext context) {
        showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lang.t('Choose Language', sw: 'Weka Lugha'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _LangOptionRow(
                    label: _lang.t('English', sw: 'Kiingereza'),
                    subtitle: _lang.t('Default language',
                        sw: 'Lugha ya moja kwa moja'),
                    active: !_lang.isSwahili,
                    onTap: () => _lang.setEnglish(),
                  ),
                  const SizedBox(height: 4),
                  _LangOptionRow(
                    label: _lang.t('Swahili', sw: 'Kiswahili'),
                    subtitle: 'Kiswahili',
                    active: _lang.isSwahili,
                    onTap: () => _lang.setSwahili(),
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
    final isDark = _theme.isDark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          _lang.t("Settings", sw: "Mipangilio"),
          style: TextStyle(
            color: isDark ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white70 : AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== PROFILE QUICK TILE =====
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: AppColors.primaryGradient),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundImage: AssetImage('assets/images/app_icon.png'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Premium Member",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lang.t("Manage your account & preferences",
                            sw: "Simamia akaunti & kinga chako"),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ===== PREFERENCES SECTION =====
          _buildSectionHeader(
            _lang.t("Preferences", sw: "Kingaokoacho"),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
                    Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // LANGUAGE — changes the WHOLE app (EN/SW) instantly.
                ListTile(
                  leading: Icon(
                    Icons.language_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  title: _buildListTileText(
                    _lang.t("Language", sw: "Lugha"),
                    isDark: isDark,
                  ),
                  subtitle: _buildListTileSubtext(
                    _lang.isSwahili
                        ? 'Swahili (Kiswahili)'
                        : 'English',
                    isDark: isDark,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _lang.isSwahili ? 'SW' : 'EN',
                      style: TextStyle(
                        color: AppColors.primaryDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  onTap: () => _showLanguagePicker(context),
                ),
                const Divider(height: 1),
                // DARK MODE — changes the WHOLE app theme instantly.
                SwitchListTile(
                  activeThumbColor: AppColors.primary,
                  title: _buildListTileText(
                    _lang.t("Dark Mode", sw: "Hali ya Giza"),
                    isDark: isDark,
                  ),
                  subtitle: _buildListTileSubtext(
                    _lang.t("Switch between light and dark theme",
                        sw: "Badilisha kati ya mandhari ya mwanga na giza"),
                    isDark: isDark,
                  ),
                  value: _theme.isDark,
                  onChanged: (val) => _theme.setDark(val),
                ),
                const Divider(height: 1),
                // PUSH NOTIFICATIONS
                SwitchListTile(
                  activeThumbColor: AppColors.primary,
                  title: _buildListTileText(
                    _lang.t("Push Notifications", sw: "Arifa za Kushusha"),
                    isDark: isDark,
                  ),
                  subtitle: _buildListTileSubtext(
                    _lang.t("Get notified for matches and gifts",
                        sw: "Pokea arifa za mapenda na zawadi"),
                    isDark: isDark,
                  ),
                  value: _notificationsEnabled,
                  onChanged: (val) =>
                      setState(() => _notificationsEnabled = val),
                ),
                const Divider(height: 1),
                // SHOW ONLINE STATUS
                SwitchListTile(
                  activeThumbColor: AppColors.primary,
                  title: _buildListTileText(
                    _lang.t("Show Online Status",
                        sw: "onyesha hali ya mtandaoni"),
                    isDark: isDark,
                  ),
                  subtitle: _buildListTileSubtext(
                    _lang.t("Let others see when you're online",
                        sw: "Weka wengine wanaoweza kuona wewe uko mtandaoni"),
                    isDark: isDark,
                  ),
                  value: _showOnlineStatus,
                  onChanged: (val) =>
                      setState(() => _showOnlineStatus = val),
                ),
              ],
            ),
          ),

                    // Security & Support Section
          _buildSectionHeader(
            _lang.t("Support & Legal", sw: "Usaidizi na Kisheria"),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.privacy_tip_rounded,
                    color: isDark ? AppColors.primary : AppColors.textPrimary,
                    size: 22,
                  ),
                  title: _buildListTileText(
                    _lang.t("Privacy Policy", sw: "Sera ya Faragha"),
                    isDark: isDark,
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white30 : Colors.black38,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    FadeSlideRoute(
                      page: const PrivacyPolicyScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.description_rounded,
                    color: isDark ? AppColors.primary : AppColors.textPrimary,
                    size: 22,
                  ),
                  title: _buildListTileText(
                    _lang.t("Terms of Service",
                        sw: "Vigawanyato vya Huduma"),
                    isDark: isDark,
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white30 : Colors.black38,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    FadeSlideRoute(
                      page: const TermsConditionsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),

                    const SizedBox(height: 30),

          // Delete Account Button
          TextButton(
            onPressed: () {},
            child: Text(
              _lang.t("Delete Account", sw: "Futa Akaunti"),
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {required bool isDark}) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white60 : AppColors.textSecondary,
      ),
    );
  }

  Widget _buildListTileText(String text, {required bool isDark}) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 15,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildListTileSubtext(String text, {required bool isDark}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: isDark ? Colors.white60 : Colors.grey.shade600,
        fontWeight: FontWeight.w300,
      ),
    );
  }

  @override
  void dispose() {
    _notificationFocusNode?.dispose();
    super.dispose();
  }
}

class _LangOptionRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  const _LangOptionRow({
    required this.label,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: active ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.primary : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
                color: active ? AppColors.primary : Colors.transparent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
          ],
        ),
      ),
    );
  }
}