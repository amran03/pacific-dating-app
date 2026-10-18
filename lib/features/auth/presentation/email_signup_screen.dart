import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';
import 'package:pacific_dating_app/core/services/auth_errors.dart';
import 'package:pacific_dating_app/core/services/email_verification_service.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/name_screen.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/gender_screen.dart';

/// Screen ya kujisajili kwa EMAIL HALISI (badala ya namba ya simu).
///
/// Mtu anaweza kuchagua "Continue with Email" kwenye Welcome. Anaingiza:
/// jina (hiari), tarehe ya kuzaliwa (hiari), email + password.
///
/// Mchakato:
///  1. signUpWithEmail -> Supabase hutuma verification code kwenye email
///     (kama "Confirm email" imewashwa). Ikiwa session irudi moja kwa moja,
///     tunaruka OTP.
///  2. Ikiwa OTP inahitajika: mtumiaji anaingiza code ya tarakimu 6 ->
///     verifyCode -> akaunti inathibitishwa.
///  3. Tuna-hifadhi `users` row, kisha tunaingia onboarding. Ikiwa jina na
///     tarehe ya kuzaliwa vilitolewa, tunaruka hatua za Name + Birthday na
///     kwenda moja kwa moja Gender (taarifa zimekwisha kuwekwa).
class EmailSignupScreen extends StatefulWidget {
  const EmailSignupScreen({super.key});

  @override
  State<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends State<EmailSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  DateTime? _birthDate;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // ---- OTP step ----
  bool _awaitingOtp = false;
  final _otpController = TextEditingController();
  bool _canResend = true;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  final _emailService = EmailVerificationService.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  int? _computedAge() {
    if (_birthDate == null) return null;
    final now = DateTime.now();
    int age = now.year - _birthDate!.year;
    if (now.month < _birthDate!.month ||
        (now.month == _birthDate!.month && now.day < _birthDate!.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, 1, 1),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }
  Future<void> _startSignup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_birthDate != null) {
      final age = _computedAge() ?? 0;
      if (age < 18) {
        _show('You must be at least 18 years old.', AppNotificationType.warning);
        return;
      }
    }

    setState(() => _isLoading = true);

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final res = await _emailService.signUpWithEmail(
        email: email,
        password: password,
        fullName: name.isEmpty ? null : name,
      );

      if (!mounted) return;

      if (res.session != null) {
        // Confirm email HAIJAwashwa — akaunti tayari, tunaruka OTP.
        await _finishAndOnboard(uid: res.user!.id);
        return;
      }

      setState(() {
        _awaitingOtp = true;
        _isLoading = false;
      });
      _startResendCooldown();
      _show('We sent a 6-digit code to $email.', AppNotificationType.info);
    } on AuthException catch (e) {
      setState(() => _isLoading = false);
      _show(friendlyAuthError(e), AppNotificationType.error);
    } catch (e) {
      setState(() => _isLoading = false);
      _show(friendlyAuthError(e), AppNotificationType.error);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      _show('Enter the 6-digit code.', AppNotificationType.warning);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _emailService.verifyCode(
        email: _emailController.text.trim(),
        token: code,
      );
      if (!mounted) return;

      final uid = res.user?.id ?? res.session?.user.id;
      if (uid == null) {
        setState(() => _isLoading = false);
        _show('Could not confirm. Please try again.', AppNotificationType.error);
        return;
      }
      await _finishAndOnboard(uid: uid);
    } on AuthException catch (e) {
      setState(() => _isLoading = false);
      _show(friendlyAuthError(e), AppNotificationType.error);
    } catch (e) {
      setState(() => _isLoading = false);
      _show(friendlyAuthError(e), AppNotificationType.error);
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;
    setState(() => _canResend = false);
    try {
      await _emailService.resendCode(email: _emailController.text.trim());
      if (!mounted) return;
      _show('Code resent. Check your inbox.', AppNotificationType.success);
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      _show(friendlyAuthError(e), AppNotificationType.error);
      setState(() => _canResend = true);
    }
  }

  void _startResendCooldown() {
    setState(() => _resendSeconds = 30);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) {
          _canResend = true;
          t.cancel();
        }
      });
    });
  }

  /// Hifadhi `users` row na uingie onboarding. Ikiwa jina na tarehe ya
  /// kuzaliwa vilitolewa, ruka Name + Birthday (nenda moja kwa moja Gender).
  Future<void> _finishAndOnboard({required String uid}) async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final birth = _birthDate;

    try {
      final Map<String, dynamic> row = {
        'uid': uid,
        'auth_email': email,
        'coins': 100,
        'notifications_enabled': true,
        'is_profile_complete': false,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (name.isNotEmpty) {
        row['name'] = name;
        row['name_lower'] = name.toLowerCase();
      }
      if (birth != null) {
        row['birth_date'] = birth.toIso8601String().substring(0, 10);
        row['age'] = _computedAge();
      }
      await Supabase.instance.client.from('users').upsert(row);

      if (!mounted) return;

      if (name.isNotEmpty && birth != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => GenderScreen(firstName: name, birthDate: birth),
          ),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const NameScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _show(friendlyAuthError(e), AppNotificationType.error);
    }
  }

  void _show(String msg, AppNotificationType type) {
    if (!mounted) return;
    showAppNotification(context, msg, type: type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: _awaitingOtp ? _buildOtpView() : _buildSignupForm(),
        ),
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          const Text(
            "Create with Email",
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            "Use your real email so we can send you a verification code.",
            style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 28),

          _label("Full name (optional)"),
          _textField(
            controller: _nameController,
            hint: "Your name",
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 18),

          _label("Birthday (optional — speeds up signup)"),
          GestureDetector(
            onTap: _pickBirthDate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _birthDate == null
                        ? "DD / MM / YYYY"
                        : "${_birthDate!.day.toString().padLeft(2, '0')} / "
                            "${_birthDate!.month.toString().padLeft(2, '0')} / ${_birthDate!.year}",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _birthDate == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Icon(Icons.calendar_today_rounded,
                      color: AppColors.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          _label("Email"),
          _textField(
            controller: _emailController,
            hint: "you@example.com",
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return "Enter your email";
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                return "Enter a valid email";
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          _label("Password"),
          _passwordField(
            controller: _passwordController,
            hint: "At least 6 characters",
            obscure: _obscurePassword,
            onToggle: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            validator: (v) {
              if ((v ?? '').length < 6) {
                return "Password must be at least 6 characters";
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          _label("Confirm password"),
          _passwordField(
            controller: _confirmController,
            hint: "Repeat password",
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            validator: (v) {
              if (v != _passwordController.text) {
                return "Passwords do not match";
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _startSignup,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.xl),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text("Create Account",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
  Widget _buildOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          "Verify your email",
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          "Enter the 6-digit code we sent to\n${_emailController.text.trim()}",
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 28),

        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: "",
            hintText: "------",
            filled: true,
            fillColor: Colors.white,
            border:
                OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.md,
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.xl),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text("Verify & Continue",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
          ),
        ),
        const SizedBox(height: 16),

        Center(
          child: TextButton(
            onPressed: _canResend ? _resendOtp : null,
            child: Text(
              _canResend
                  ? "Resend code"
                  : "Resend code in ${_resendSeconds}s",
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 8),

        Center(
          child: TextButton(
            onPressed: () => setState(() => _awaitingOtp = false),
            child: const Text("Change email",
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.primary),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border:
            OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
        suffixIcon: IconButton(
          icon: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: onToggle,
        ),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border:
            OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
