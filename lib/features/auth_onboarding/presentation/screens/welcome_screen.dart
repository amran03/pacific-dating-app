import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/auth_errors.dart';
import 'package:pacific_dating_app/core/services/google_auth_service.dart';
import 'package:pacific_dating_app/features/auth/presentation/create_password_screen.dart';
import 'package:pacific_dating_app/features/auth/presentation/login_screen.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/name_screen.dart';
import 'package:pacific_dating_app/features/dashboard/presentation/screens/main_dashboard_screen.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  // Float animation: app icon gently floats up/down (alive feeling).
  late final AnimationController _floatController;

  bool _isGoogleLoading = false;

  /// GOOGLE SIGN-IN — akaunti mpya ya Google: tengeneza users row (jina,
  /// avatar, email kutoka Google) na anza onboarding (Name -> Birthday ->
  /// Gender -> Photos). Mtumiaji wa zamani aliye-kamilisha profile anaingia
  /// dashboard moja kwa moja. AuthGate kwenye root pia inasikiliza session.
  Future<void> _continueWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final result = await GoogleAuthService.instance.signInWithGoogle();
      // null = mtumiaji alighairi chaguo (si hitilafu).
      if (result == null || !mounted) return;

      if (result.profileComplete) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainDashboardScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const NameScreen()),
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      showAppNotification(
        context,
        friendlyAuthError(e),
        color: Colors.redAccent,
      );
    } catch (e) {
      if (!mounted) return;
      // Kamwe onyeshi ujumbe mbichi ($e) — friendlyAuthError hurudisha
      // ujumbe rafiki (mtandao / hitilafu ya kawaida) + raw kwenye debug.
      showAppNotification(
        context,
        'Google sign-in failed. ${friendlyAuthError(e)}',
        color: Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  /// Popup ya CREATE ACCOUNT — inaomba EMAIL (badala ya namba ya simu).
  /// Baada ya kuendelea, CreatePasswordScreen inaundia akaunti na kutuma
  /// OTP ya tarakimu 6 kwenye email hiyo kuthibitisha (mfumo wa OTP).
  void _showEmailInputSheet(BuildContext parentContext) {
    final TextEditingController emailController = TextEditingController();

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: AppRadius.sm,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Enter Your Email',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We will send a verification code (OTP) to confirm it is you.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: AppRadius.md,
                      ),
                      child: TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          hintText: "you@example.com",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.xl,
                          ),
                        ),
                        onPressed: () {
                          final String email = emailController.text.trim();

                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(email)) {
                            showAppNotification(
                              sheetContext,
                              'Enter a valid email address.',
                              color: Colors.redAccent,
                            );
                            return;
                          }

                          Navigator.pop(sheetContext);
                          Navigator.push(
                            parentContext,
                            MaterialPageRoute(
                              builder: (context) => CreatePasswordScreen(
                                email: email,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          'Continue',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
            child: Stack(
              children: [
                // Decorative gradient circles (background art)
                Positioned(
                  top: -70,
                  left: -60,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                Positioned(
                  top: 90,
                  right: -80,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryDark.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -60,
                  left: -40,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.07),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),

                      // APP ICON — inaelea juu-chini taratibu, yenye glow.
                      AnimatedBuilder(
                        animation: _floatController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, -8 * _floatController.value),
                            child: child,
                          );
                        },
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) {
                            return Transform.scale(scale: value, child: child);
                          },
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.xl,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryDark
                                      .withValues(alpha: 0.35),
                                  blurRadius: 30,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: AppRadius.xl,
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: AppColors.primaryGradient,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.favorite_rounded,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // TITLE
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, 30 * (1 - value)),
                            child: Opacity(
                              opacity: value,
                              child: child,
                            ),
                          );
                        },
                        child: const Text(
                          "Pacific",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1000),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: Opacity(
                              opacity: value,
                              child: Text(
                                'Find your life partner\nWithout stress, more safely.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w300,
                                  height: 1.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: AppRadius.xl,
                                      gradient: const LinearGradient(
                                        colors: AppColors.primaryGradient,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryDark
                                              .withValues(alpha: 0.4),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              AppRadius.xl,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _showEmailInputSheet(context),
                                      child: Text(
                                        'Create Account',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const SizedBox(height: 12),
                                // GOOGLE SIGN-IN — akaunti mpya: onboarding;
                                // ya zamani (profile kamili): dashboard.
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: AppColors.primary,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppRadius.xl,
                                      ),
                                    ),
                                    onPressed: _isGoogleLoading
                                        ? null
                                        : _continueWithGoogle,
                                    icon: _isGoogleLoading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.primaryDeep,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.g_mobiledata_rounded,
                                            size: 30,
                                            color: AppColors.primaryDeep,
                                          ),
                                    label: const Text(
                                      'Continue with Google',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryDeep,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: AppColors.primary,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppRadius.xl,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const LoginScreen(),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Log In',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryDeep,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
  }
}


