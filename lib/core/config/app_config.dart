/// Central app configuration.
///
/// Supabase credentials can be supplied in two ways:
///
/// 1. RECOMMENDED — via --dart-define (keeps secrets out of source control):
///    flutter run \
///      --dart-define=SUPABASE_URL=https://xxxxxxxx.supabase.co \
///      --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
///    And for building:
///    flutter build apk \
///      --dart-define=SUPABASE_URL=https://xxxxxxxx.supabase.co \
///      --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// 2. QUICK — paste them directly into the fallback constants below
///    (Settings > API in your Supabase dashboard).
///
/// NOTE: Only the PUBLISHABLE / anon key belongs in a client app.
/// The SECRET (service_role) key must never be embedded in an app —
/// anyone can extract it from the APK and take over your database.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ithbeyiqtyfebtmkcugv.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_DZ9XtTzElbFri457XFRlJw_HvzcDVyX',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.startsWith('http') &&
      supabasePublishableKey.startsWith('sb_publishable_') &&
      supabasePublishableKey.length > 20;
}
