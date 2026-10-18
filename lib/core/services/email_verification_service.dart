import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper rahisi kwa ajili ya uthibitishaji kwa email (OTP) kupitia Supabase.
///
/// Supama inatuma verification code (digits 6) kwenye email ya mtumiaji
/// (kama "Confirm email" imewashwa kwenye Supabase, au tunapoitisha
/// kwa [resend]). Tunaitumia kwa:
///  - kuthibitisha email mpya wakati wa sign-up (email kweli).
///  - kuweka email ya kurekebji kwa akaunti iliundwa kwa namba ya simu.
class EmailVerificationService {
  EmailVerificationService._();
  static final EmailVerificationService instance =
      EmailVerificationService._();

  final _auth = Supabase.instance.client.auth;

  /// Sign-up kwa email HALISI (kama mtu amechagua "Sign in with Email").
  ///
  /// Kurudisha [AuthResponse] ili UI iweze kupanga:
  ///  - `session != null`  -> akaunti iko tayari (email confirm HAJAwashwa).
  ///  - `session == null`  -> tuma OTP; mtumiaji anapaswa kuthibitisha.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
    String? dataRedirectTo,
  }) async {
    return _auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
      emailRedirectTo: dataRedirectTo,
    );
  }

  /// Tuma (au tuma tena) verification code kwenye email.
  Future<void> resendCode({
    required String email,
    OtpType type = OtpType.signup,
  }) async {
    await _auth.resend(type: type, email: email.trim());
  }

  /// Thibitisha code (digits 6) iliyoletwa na mtumiaji.
  /// Inafanikisha session kwenye Supabase (mtumiaji anaingia).
  Future<AuthResponse> verifyCode({
    required String email,
    required String token,
    OtpType type = OtpType.signup,
  }) async {
    return _auth.verifyOTP(
      type: type,
      token: token.trim(),
      email: email.trim(),
    );
  }

  /// Badilisha email ya akaunti iliyopo + tuma code ya uthibitishaji
  /// (kwa akaunti za simu zinazotaka kuweka email ya kurekebji).
  Future<void> updateEmailAndSendCode(String newEmail) async {
    await _auth.updateUser(
      UserAttributes(email: newEmail.trim()),
    );
  }

  /// Thibitisha email mpya baada ya [updateEmailAndSendCode].
  Future<AuthResponse> verifyEmailChange({
    required String currentEmail,
    required String newEmail,
    required String token,
  }) async {
    return _auth.verifyOTP(
      type: OtpType.emailChange,
      token: token.trim(),
      email: currentEmail.trim(),
    );
  }

  bool get isEmailConfirmed {
    final u = _auth.currentUser;
    if (u == null) return false;
    return (u.emailConfirmedAt ?? '').isNotEmpty;
  }

  String? get currentEmail => _auth.currentUser?.email;

  /// Debug helper — inasaidia kuelewa hali ya uthibitishaji.
  void debugDumpSession() {
    final u = _auth.currentUser;
    debugPrint('email=${u?.email} '
        'emailConfirmedAt=${u?.emailConfirmedAt}');
  }
}
