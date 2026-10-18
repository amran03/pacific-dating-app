# GOOGLE LOGIN SETUP — Google Cloud Console + Supabase

Mtiririko uliotumika: **native idToken** (`google_sign_in` →
`Supabase.auth.signInWithIdToken`). Hakuna browser wala intent-filter —
app inaonyesha akaunti za Google zilizosajiliwa kwenye device moja kwa moja.

Muundo: `lib/core/services/google_auth_service.dart` + button kwenye
`welcome_screen.dart` na `login_screen.dart`.

---

## 1. Google Cloud Console (one-time)

1. Fungua <https://console.cloud.google.com> na chagua project
   **pacific-dating-app** (ile ile ya Firebase — Google Cloud na Firebase
   zinashiriki project moja).
2. **OAuth consent screen** (APIs & Services > OAuth consent screen):
   - User Type: `External`
   - App name: `Pacific`
   - Support email + Developer contact: weka zako
   - Scopes: ongeza `email`, `profile`, `openid`
   - **Test users**: ongeza email za mtihani (rangi ya "Testing", mtu
     yeyote hana ruhusa — ongeza akaunti zako za Google hapa)
   - Ukishatokuwa na mipaka: bonyeza **Publish app** (Production)
3. **Credentials** (APIs & Services > Credentials) >
   **Create Credentials > OAuth client ID** — tengeneza MBILE:

   ### a) Android client (kwa kuingia kwenye simu)
   - Application name: `Pacific (Android)`
   - Package name: `com.example.pacific_dating_app`
   - SHA-1 certificate fingerprint (maendeleo / debug):
     `8C:2C:8F:DE:18:B4:99:E0:67:1A:47:6A:4E:59:CF:18:C1:4A:45:53`
   - Tengeneza Android client **ya pili** kwa release (APK iliyosainiwa):
     package moja + SHA-1 hii:
     `1C:31:86:34:DA:2F:6E:6C:59:33:19:E6:95:97:80:63:29:4E:66:8A`
   > SHA hizi zimetengenezwa kutoka `~/.android/debug.keystore` na
   > `android/app/upload-keystore.jks`. Kama utabadilisha keystore,
   > kaza upya: `keytool -list -v -keystore <file> -alias <alias>`

   ### b) Web application client (kwa Supabase)
   - Name: `Pacific (Web)`
   - Authorized JavaScript origins: (hiari kwa dev: `http://localhost`)
   - Authorized redirect URIs:
     `https://ithbeyiqtyfebtmkcugv.supabase.co/auth/v1/callback`
   - Nakili **Client ID** na **Client Secret** (Client Secret
     huonyeshwa mara moja tu utakapoitengeneza — hifadhi salama)

4. **Firebase** (kwa FCM — tayari ipo, lakini hakikisha):
   Firebase Console > Project settings > General > Your apps (Android,
   `com.example.pacific_dating_app`) > **Add fingerprint** — ongeza SHA-1
   ya debug na ya release kama hapo juu, kisha pakua `google-services.json`
   mpya na uiweke `android/app/`.

## 2. Supabase (one-time)

1. Dashboard > **Authentication > Providers > Google**: weka **Enable**
2. **Client ID** = Web Client ID (si ya Android!), **Client Secret** =
   Web Client Secret (hatua 1.3b)
3. Supabase itaonyesha redirect URL yake
   (`https://ithbeyiqtyfebtmkcugv.supabase.co/auth/v1/callback`) —
   hakikisha ipo kwenye Authorized redirect URIs ya Web client

## 3. Kuweka Web Client ID kwenye app

Njia inayopendekezwa (bila kubadilisha kodi):

```
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<WEB_CLIENT_ID>.apps.googleusercontent.com
```

Au weka moja kwa moja kwenye
`lib/core/services/google_auth_service.dart > webClientId`
(kwenye `defaultValue`).

Kama iachwa tupu na `google-services.json` ikiwa na web client ndaniyo,
plugin hutumia `default_web_client_id` kutoka kwenye hiyo json.

## 4. Kujaribu

1. Bonyeza **Continue with Google** (Welcome au Log In screen)
2. Chagua akaunti → idToken inathibitishwa → Supabase session
3. **Mtumiaji mpya**: `users row` inaundwa na jina/avatar/email ya Google
   (coins 100, kama phone signup) → onboarding: Name → Birthday → Gender
   → Photos
4. **Mtumiaji wa zamani** aliye-kamilisha profile: dashboard moja kwa moja
5. Google haiompi OTP — email tayari imethibitishwa na Google

## Matatizo yanayojitokeza

| Hitilafu | Sababu | Suluhisho |
| --- | --- | --- |
| `DEVELOPER_ERROR` / code 10 | SHA-1 haijaongezwa au package tofauti | Ongeza SHA-1 sahihi; hakikisha applicationId ni `com.example.pacific_dating_app` |
| "Google haikupa idToken" | Hakuna Android OAuth client | Tengeneza Android client (hatua 1.3a) |
| `provider is not enabled` | Google haijawashwa Supabase | Authentication > Providers > Google > Enable |
| `invalid request / audience` | Web Client ID si ile ile ya `serverClientId` | Hakikisha unatumia **Web** client ID, si Android |
| "Access blocked: app hasn't been verified" | Consent screen iko "Testing" | Ongeza akaunti kwenye Test users au Publish app |
| Release APK haifanyi kazi | SHA-1 ya keystore ya release haijaongezwa | Ongeza Android client ya release (hatua 1.3a, ya pili) |

## Usalama

- Web Client ID si siri (inaonekana kwenye APK/network) — SIRI ni
  **Client Secret** (inaishi Supabase pekee, wala kwenye app).
- `google_sign_in` haifichui password yoyote — Google hutoa idToken tu.
