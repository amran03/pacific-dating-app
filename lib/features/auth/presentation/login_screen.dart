import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/services/auth_errors.dart';
import 'package:pacific_dating_app/features/dashboard/presentation/screens/main_dashboard_screen.dart';
import 'package:pacific_dating_app/features/auth/presentation/reset_password_screen.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/welcome_screen.dart';
import 'package:pacific_dating_app/features/auth/presentation/create_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordHidden = true;
  bool _isLoading = false;

  Future<void> _login() async {
    final String rawInput = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (rawInput.isEmpty || password.isEmpty) {
      _showMessage("Tafadhali jaza email/namba ya simu na password.", Colors.redAccent);
      return;
    }

    final String email = rawInput.contains('@') ? rawInput : phoneToSyntheticEmail(rawInput);

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      _showMessage("Umeingia kikamilifu!", Colors.green);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainDashboardScreen()),
            (route) => false,
      );
    } on AuthException catch (e) {
      _showMessage(friendlyAuthError(e), Colors.redAccent);
    } catch (e) {
      _showMessage("Kosa: ${e.toString()}", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Title Header
              const Text(
                "Karibu Tena!",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Ingiza namba yako ya simu na password kuendelea.",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Input: Phone Number
              const Text(
                "Phone Number",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone_android_rounded, color: AppColors.primary),
                    hintText: "0712345678",
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Input: Password
              const Text(
                "Password",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _passwordController,
                  obscureText: _isPasswordHidden,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordHidden = !_isPasswordHidden;
                        });
                      },
                    ),
                    hintText: "Ingiza password",
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),

              // Reset Password Button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ResetPasswordScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    "Umesahau Password?",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Log In Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    "Log In",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Create Account Redirect Button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Huna akaunti? ",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                      );
                    },
                    child: const Text(
                      "Create Account",
                      style: TextStyle(
                        color: AppColors.primary,
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
    );
  }
}
