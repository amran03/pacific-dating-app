import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_color.dart';
import '../../../../core/services/auth_errors.dart';
import '../../../../features/profile/presentation/screens/terms_conditions_screen.dart';
import '../../../../features/profile/presentation/screens/privacy_policy_screen.dart';
import 'create_password_screen.dart' show phoneToSyntheticEmail;
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _phoneToInternalEmail(String rawPhone) {
    return phoneToSyntheticEmail(rawPhone);
  }

  Future<void> _onSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String phone = _phoneController.text.trim();
    final String name = _nameController.text.trim();
    final String password = _passwordController.text.trim();
    final String internalEmail = _phoneToInternalEmail(phone);

    try {
      final AuthResponse response = await Supabase.instance.client.auth.signUp(
        email: internalEmail,
        password: password,
        data: {'full_name': name},
      );

      final user = response.user;
      if (user == null) throw Exception("User creation failed");

      await Supabase.instance.client.from('users').upsert({
        'uid': user.id,
        'name': name,
        'phone_number': phone,
        'is_profile_complete': false,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Akaunti imetengenezwa! Karibu."),
          backgroundColor: Colors.green,
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyAuthError(e)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Hitilafu isiyotarajiwa: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: AppColors.primaryGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryDark.withValues(alpha: 0.4),
                            blurRadius: 26,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  "Create Account",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Find your perfect match today 💕",
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: "Full Name",
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.primaryDeep,
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter your name";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: "Phone Number",
                    hintText: "e.g. 0712345678",
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(
                      Icons.phone_outlined,
                      color: AppColors.primaryDeep,
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter your phone number";
                    }
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 9) {
                      return "Please enter a valid phone number";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: "Password",
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.primaryDeep,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return "Password must be at least 6 characters";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        colors: AppColors.primaryGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryDark.withValues(alpha: 0.45),
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
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _isLoading ? null : _onSignUp,
                      child: _isLoading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                          : const Text(
                        "Sign Up",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Center(
                  child: Text.rich(
                    TextSpan(
                      text: "Kwa kuendelea unakubali ",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                const TermsConditionsScreen(),
                              ),
                            ),
                            child: const Text(
                              "Terms & Conditions",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.linkBlue,
                              ),
                            ),
                          ),
                        ),
                        TextSpan(
                          text: " na ",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                const PrivacyPolicyScreen(),
                              ),
                            ),
                            child: const Text(
                              "Privacy Policy",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.linkBlue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? "),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Log In",
                        style: TextStyle(
                          color: AppColors.primaryDeep,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
