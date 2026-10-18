import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// GOOGLE SIGN-IN — mtumiriko wa native kwa Supabase (idToken).
// ============================================================
//
// Mtiririko (si OAuth web flow — hakuna browser/intent-filter):
//   1. google_sign_in inaonyesha orodha ya akaunti za Google kwenye device
//   2. Inarudisha idToken (audience = Web Client ID) + accessToken
//   3. Supabase.auth.signInWithIdToken(provider: google, ...) — session
//      inaundwa moja kwa moja; hakuna email verification kwa Google
//   4. Akaunti MPYA: tunatengeneza users row na taarifa za Google
//      (jina, avatar, email) — bado inahitaji onboarding (birthday,
//      gender, photos) kama ilivyo kwa phone signup
//
// MAWAKALA YA GOOGLE CLOUD CONSOLE (one-time — tazama
// docs/GOOGLE_LOGIN_SETUP.md kwa hatua kamili):
//   - Android OAuth client: package name + SHA-1 (debug NA release)
//   - Web OAuth client: Client ID ndiyo [webClientId] hapa chini
//     (au iache --dart-define=GOOGLE_WEB_CLIENT_ID=...)
//   - Supabase > Auth > Providers > Google: weka Web Client ID + Secret
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  /// WEB CLIENT ID (Google Cloud Console > Credentials > OAuth 2.0
  /// Client IDs > "Web application"). Inatumika kama audience ya idToken
  /// inayoidhinishwa na Supabase.
  ///
  /// Weka kwa njia mojawapo:
  ///   - `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com`
  ///   - au weka moja kwa moja hapa chini (defaultValue)
  ///
  /// Ikiachwa tupu, plugin hutumia `default_web_client_id` kutoka
  /// google-services.json (hakikishwa faili imesasishwa ikiwa na web
  /// client — Firebase Console > Project settings > General >
  /// Your apps > Add credentials).
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  GoogleSignIn get _google => GoogleSignIn(
        serverClientId: webClientId.isEmpty ? null : webClientId,
      );

  /// Inaingia kwa Google.
  ///
  /// Rudisha `null` mtumiaji alichagua kughairi mchakato (si hitilafu).
  /// Rudisha `{ profileComplete: true }` mtumiaji yuko tayari kuingia
  /// dashboard; `{ profileComplete: false }` akaunti mpya au bado
  /// onboarding — mwongoze kwenye NameScreen.
  ///
  /// Inaitupia hitilafu (AuthException au ujumbe rahisi) — msimamizi
  /// wa UI ndio anaonyesha ujumbe kwa mtumiaji.
  Future<({bool profileComplete})?> signInWithGoogle() async {
    // 1. Chagua akaunti ya Google kwenye device.
    final GoogleSignInAccount? googleUser = await _google.signIn();
    if (googleUser == null) return null; // mtumiaji alighairi

    // 2. Pata idToken/accessToken.
    final GoogleSignInAuthentication auth = await googleUser.authentication;
    final String? idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google haikupa idToken. Hakikisha Android OAuth client ipo kwenye '
        'Google Cloud Console (package + SHA-1) na google-services.json '
        'imesasishwa.',
      );
    }

    // 3. Supabase session kupitia idToken (email tayari imethibitishwa
    //    na Google — hakuna OTP).
    final AuthResponse res =
        await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );

    final user = res.user;
    if (user == null) {
      throw Exception('Supabase haikurudisha mtumiaji baada ya Google sign-in.');
    }

    // 4. Angalia kama users row ipo (AuthGate inaangalia row hii
    //    kuamua: dashboard vs onboarding).
    final existing = await Supabase.instance.client
        .from('users')
        .select('uid, is_profile_complete')
        .eq('uid', user.id)
        .maybeSingle();

    if (existing == null) {
      // Akaunti MPYA ya Google — tengeneza row na taarifa za Google.
      final meta = user.userMetadata ?? const <String, dynamic>{};
      final String name = (meta['full_name'] ?? meta['name'] ?? '').toString();
      final String email = (meta['email'] ?? googleUser.email).toString();
      final String avatar =
          (meta['avatar_url'] ?? meta['picture'] ?? '').toString();
      await Supabase.instance.client.from('users').upsert({
        'uid': user.id,
        'name': name,
        'name_lower': name.toLowerCase(),
        'auth_email': email,
        'profile_image_url': avatar,
        'coins': 100,
        'is_profile_complete': false,
        'notifications_enabled': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return (profileComplete: false);
    }

    return (profileComplete: existing['is_profile_complete'] == true);
  }

  /// Ondoa session ya Google (inatumika na logout ikiwa unahitaji kuhakikisha
  /// mtumiaji huchaguliwi tena otomatiki wakati wa login ijayo).
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
  }



}
