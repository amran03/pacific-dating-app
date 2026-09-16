/// Maps raw Supabase auth errors to friendly, user-facing English messages.
/// The raw API strings like "Email rate limit exceeded" are confusing;
/// this gives a clear message + what to do instead.
String friendlyAuthError(Object error) {
  final String raw = error.toString().toLowerCase();

  if (raw.contains('network') ||
      raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection')) {
    return 'No internet connection or the server is unreachable. '
        'Turn on your data/WiFi and try again.';
  }

  if (raw.contains('rate limit') ||
      raw.contains('too many') ||
      raw.contains('limit exceeded') ||
      raw.contains('exceeded')) {
    return 'Too many attempts (rate limit). '
        'Wait 1 minute and try again. If it continues, increase the rate limit '
        'in: Supabase > Authentication > Rate Limits.';
  }
  if (raw.contains('user not found') ||
      raw.contains('no user found') ||
      raw.contains('user does not exist')) {
    return 'No account found with these details. Create an account first '
        '(Create Account).';
  }
  if (raw.contains('email not confirmed') || raw.contains('unconfirmed')) {
    return 'Your account is not confirmed via email yet. Turn off '
        '"Confirm email" in: Supabase > Authentication > Providers > Email.';
  }
  if (raw.contains('invalid login')) {
    return 'Email/phone number or password is incorrect.';
  }
  if (raw.contains('already registered') ||
      raw.contains('already been registered')) {
    return 'An account already exists with this email/number. '
        'Continue to Log In instead.';
  }
  if (raw.contains('weak password') || raw.contains('at least 6')) {
    return 'Password must be at least 6 characters.';
  }
  if (raw.contains('signups not allowed') || raw.contains('signup disabled')) {
    return 'New sign-ups are disabled. Enable it in: Supabase > '
        'Authentication > Sign In / Up > Allow new users.';
  }
  return error.toString();
}
