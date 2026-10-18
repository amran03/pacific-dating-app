import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pacific_dating_app/core/constants/app_color.dart';
import 'package:pacific_dating_app/core/config/app_config.dart';
import 'package:pacific_dating_app/core/services/auth_errors.dart';
import 'package:pacific_dating_app/features/auth_onboarding/presentation/screens/name_screen.dart';
import 'package:pacific_dating_app/core/widgets/app_notification_overlay.dart';
import 'package:pacific_dating_app/core/constants/app_radius.dart';

/// Hubadilisha namba ya simu kuwa "email ya kubuni" (synthetic email).
/// Inashughulikia formats zote za kawaida za TZ: 0712345678, 712345678,
/// +255712345678, +255 (0) 712-345-678 n.k.
///
/// Domain: AppConfig.syntheticEmailDomain — LAZIMA liwe na MX records
/// (GoTrue inakagua DNS) vinginevyo signup ya simu yote inaonekana
/// "Email address is invalid".
String phoneToSyntheticEmail(String phoneNumberOrDigits) {
  String digits = phoneNumberOrDigits.replaceAll(RegExp(r'[^0-9]'), '');

  // Ondoa country code kama ipo, kisha ondoka 0 ya mwanzo (local format),
  // hatimaye weka 255 upande.
  if (digits.startsWith('255')) {
    digits = digits.substring(3);
  }
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  digits = '255$digits';

  return "$digits@${AppConfig.syntheticEmailDomain}";
}

class CreatePasswordScreen extends StatefulWidget {
  /// Namba ya simu (mtiririko wa zamani — screens za profile_setup /
  /// setup_account bado zinaitumia).
  final String? phoneNumber;

  /// Email halisi (mtiririko mpya wa Create Account kwenye Welcome).
  /// Ikiwekwa, akaunti inathibitishwa kwa OTP ya tarakimu 6 kabla ya
  /// onboarding (badala ya namba ya simu).
  final String? email;

  const CreatePasswordScreen({
    super.key,
    this.phoneNumber,
    this.email,
  }) : assert(phoneNumber != null || email != null, 'Weka phoneNumber AU email');

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isPasswordHidden = true;
  bool _isConfirmHidden = true;
  bool _isLoading = false;

  // ---- OTP step (email mode) ----
  bool _awaitingOtp = false;
  final TextEditingController _otpController = TextEditingController();
  bool _canResend = true;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  /// Email ya kuingia (halisi au synthetic kwa simu).
  String get _signUpEmail => widget.email?.trim() ??
      phoneToSyntheticEmail(widget.phoneNumber ?? '');

  Future<void> _createPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String password = _passwordController.text.trim();

    try {
      // 1. Tengeneza akaunti mpya ya Supabase Auth (email halisi kwa
      //    Create Account; synthetic email kwa mtiririko wa simu).
      final AuthResponse response = await Supabase.instance.client.auth.signUp(
        email: _signUpEmail,
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception("User creation failed");

      // Email confirmation ikiwa IMEWASHWA Supabase, signUp inarudisha
      // user bila session.
      if (response.session == null) {
        if (!mounted) return;
        final bool alreadyRegistered =
            user.identities == null || user.identities!.isEmpty;
        if (alreadyRegistered) {
          _showMessage(
            "This account already exists — please log in with Log In.",
            Colors.orange,
          );
          Navigator.pop(context);
          return;
        }

        // EMAIL + OTP: akaunti imeandikwa na Supabase imetuma code ya
        // tarakimu 6 kwenye email — onyesha hatua ya kuthibitisha.
        if (widget.email != null) {
          setState(() {
            _awaitingOtp = true;
            _isLoading = false;
          });
          _startResendCooldown();
          _showMessage(
            "We sent a 6-digit code to ${widget.email}.",
            Colors.green,
          );
          return;
        }

        // Mtiririko wa simu (synthetic email haipokei barua pepe) —
        // inahitaji 'Confirm email' imewashwa kwenye Supabase.
        _showMessage(
          "Account created, but it needs verification. Turn off 'Confirm "
          "email' in: Supabase > Authentication > Sign In / Up.",
          Colors.orange,
        );
        Navigator.pop(context);
        return;
      }

      // Session ipo (Confirm email HAIJAwashwa) — hifadhi na uanze
      // onboarding (Name -> Birthday -> Gender -> Photos).
      await _finishSignup(uid: user.id);
    } on AuthException catch (e) {
      _showMessage(friendlyAuthError(e), Colors.redAccent);
    } catch (e) {
      // Kamwe ujumbe mbichi (error.toString()) kwa mtumiaji — rafiki tu
      // (mtandao/hitilafu) + raw kwenye debug.
      _showMessage(friendlyAuthError(e), Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Hifadhi `users` row na uingie onboarding. Mtiririko wa email hauweki
  /// phone_number (watumiaji wa email hawana simu kwenye akaunti).
  Future<void> _finishSignup({required String uid}) async {
    await Supabase.instance.client.from('users').upsert({
      'uid': uid,
      if (widget.email == null) 'phone_number': widget.phoneNumber,
      'auth_email': _signUpEmail,
      'coins': 100,
      'is_profile_complete': false,
      'notifications_enabled': true,
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;

    // Anza onboarding (Name -> Birthday -> Gender -> Photos) na futa
    // stack ya nyuma ili user asirudi kwenye screens za auth.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const NameScreen()),
      (route) => false,
    );
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    showAppNotification(context, message, color: color);
  }

  // ============================================================
  // OTP (email mode) — code ya tarakimu 6 iliyotumwa kwenye email.
  // ============================================================

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      _showMessage('Enter the 6-digit code.', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.signup,
        token: code,
        email: widget.email!.trim(),
      );
      if (!mounted) return;

      final uid = res.user?.id ?? res.session?.user.id;
      if (uid == null) {
        setState(() => _isLoading = false);
        _showMessage('Could not confirm. Please try again.', Colors.redAccent);
        return;
      }
      await _finishSignup(uid: uid);
    } on AuthException catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showMessage(friendlyAuthError(e), Colors.redAccent);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showMessage(friendlyAuthError(e), Colors.redAccent);
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;
    setState(() => _canResend = false);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email!.trim(),
      );
      _showMessage('Code resent. Check your inbox.', Colors.green);
      _startResendCooldown();
    } catch (e) {
      _showMessage(friendlyAuthError(e), Colors.redAccent);
      if (mounted) setState(() => _canResend = true);
    }
  }

  void _startResendCooldown() {
    if (!mounted) return;
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

  /// OTP view — inaonyeshwa badala ya fomu ya password mtumiaji
  /// akiwa amekamilisha hatua ya kwanza (akaunti imetengenezwa).
  Widget _buildOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.mark_email_read_rounded,
            size: 36,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Verify Your Email ✉️",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We sent a 6-digit code to ${widget.email}. Enter it below to "
          "finish creating your account.",
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          "6-digit code",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            letterSpacing: 8,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            counterText: "",
            hintText: "000000",
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: AppRadius.md,
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _canResend ? _resendOtp : null,
            child: Text(
              _canResend ? "Resend code" : "Resend in ${_resendSeconds}s",
              style: TextStyle(
                color: _canResend
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
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
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    "Verify & Continue",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: _awaitingOtp
              ? _buildOtpView()
              : Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_person_rounded, size: 36, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Set Your Password 🔒",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  "Create the password you'll use with ${widget.email ?? widget.phoneNumber} every time you log in.",
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 32),

                const Text("Password", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _isPasswordHidden,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _isPasswordHidden = !_isPasswordHidden),
                    ),
                    hintText: "At least 6 characters",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return "Password must be at least 6 characters";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                const Text("Confirm Password", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _isConfirmHidden,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: Icon(_isConfirmHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _isConfirmHidden = !_isConfirmHidden),
                    ),
                    hintText: "Repeat password",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide.none),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
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
                    onPressed: _isLoading ? null : _createPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.xl),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      "Complete & Continue",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
