/// Maps raw Supabase auth errors to friendly, user-facing (Swahili) messages.
/// The raw API strings like "Email rate limit exceeded" are confusing and
/// untranslated; this gives a clear message + what to do instead.
String friendlyAuthError(Object error) {
  final String raw = error.toString().toLowerCase();

  if (raw.contains('rate limit') ||
      raw.contains('too many') ||
      raw.contains('limit exceeded') ||
      raw.contains('exceeded')) {
    return 'Email imetumwa mara nyingi sana (rate limit). Subiri dakika 1 '
        'na ujaribu tena. Kama inaendelea, ongeza rate limit kwenye: '
        'Supabase > Authentication > Rate Limits.';
  }
  if (raw.contains('email not confirmed') || raw.contains('unconfirmed')) {
    return 'Akaunti bado haijathibitishwa kwa email. Zima "Confirm email" '
        'kwenye: Supabase > Authentication > Providers > Email.';
  }
  if (raw.contains('invalid login')) {
    return 'Email/namba ya simu au password si sahihi.';
  }
  if (raw.contains('already registered') || raw.contains('already been registered')) {
    return 'Akaunti tayari ipo kwa email/namba hii. Endelea kwenye Log In.';
  }
  if (raw.contains('weak password') || raw.contains('at least 6')) {
    return 'Password lazima iwe angalau herufi 6.';
  }
  if (raw.contains('signups not allowed') || raw.contains('signup disabled')) {
    return 'Usajili mpya umezimitishwa. Washa kwenye: Supabase > '
        'Authentication > Sign In / Up > Allow new users.';
  }
  return error.toString();
}