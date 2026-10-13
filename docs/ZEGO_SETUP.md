# ZEGOCLOUD Setup — Pacific Dating App

1-on-1 voice & video calls kupitia `zego_uikit_prebuilt_call` + signaling plugin.

## 1. Credentials (source HAIJUI siri)

| Credential | Njia |
|---|---|
| AppID | `1740448927` (default ndani ya `ZegoCallService.appID`; badilisha kwa `--dart-define=ZEGO_APP_ID=...`) |
| AppSign | **Tu** `--dart-define=ZEGO_APP_SIGN=<appsign>` — hakuna kwenye source |
| ResourceID | `pacific_call` (`ZegoCallService.resourceID`) |

Run command:

```bash
flutter run --dart-define=ZEGO_APP_SIGN=<appsign>
```

Bila `ZEGO_APP_SIGN`, ZegoService haianzi (ujumbe uonekane kwenye console), lakini app nyingine zote zinafanya kazi.

## 2. ZEGO Console (console.zegocloud.com)

1. **Projects → AppID 1740448927 → Call (1-on-1 Calling / Call Invitation)** — weka "Call Invitation" ON.
2. **ResourceID**: ongeza resource ID `pacific_call` (inatumika kwa offline push; lazima iendane na `ZegoCallService.resourceID`).
3. **Offline call notification (Android)** — weka:
   - Channel ID: `pacific_calls_high_priority` (lazima iendane na `callChannel.channelID` kwenye `zego_call_service.dart`)
   - Channel name: `Incoming calls`
   - Sound/ringtone: chagua kutoka ZEGO, **au** weka `android/app/src/main/res/raw/<name>.mp3` na set `callChannel.sound: '<name>'`
4. **FCM credentials** (kwa app ikiwa killed — offline push):
   - Firebase Console → **Project settings → Cloud Messaging → HTTP API (Legacy) → Server key** (au Service Account JSON kwa FCM HTTP v1), pakua na upload kwenye ZEGO Console → **Push/FCM** section (uweke `google-services.json` pia, hatua 3 hapa chini).

## 3. FCM (Android)

1. Firebase Console → **Add project** (au tumia ile ipo) → **Add app → Android** → package name: `com.example.pacific_dating_app`.
2. Pakua `google-services.json` → weka: `android/app/google-services.json`.
   - `android/app/build.gradle.kts` tayari ina `apply(plugin = "com.google.gms.google-services")` **masharti json ipo** — build haifeli bila json.
3. `android/build.gradle.kts` tayari ina classpath `com.google.gms:google-services:4.4.1`.
4. ZEGO Console → FCM section → weka server key / service account (hatua 2.4 hapo juu).
5. Rebuild: `flutter clean && flutter run --dart-define=ZEGO_APP_SIGN=<appsign>`.

## 4. Android manifest (tayari imewekwa)

- Permissions: `CAMERA`, `RECORD_AUDIO`, `INTERNET`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH`, `BLUETOOTH_CONNECT`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `WAKE_LOCK`, `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`.
- `android:launchMode="singleInstance"` (ZEGO inahitaji kwa `showFullScreen: true`).
- `minSdk = maxOf(flutter.minSdkVersion, 21)`.
- ProGuard: `android/app/proguard-rules.pro` (ZEGO keep-rules; zinatumika R8 ikiwashwa).

## 5. Runtime permissions

- **Outgoing**: chat screen huomba `microphone` (voice) / `camera` + `microphone` (video) kabla ya kutuma invitation (`_ensureCallPermissions`); ukikataa → ujumbe wa hitaji na invitation haitelekwi.
- **Incoming**: Zego huomba `ZegoCallInvitationConfig.permissions` (default: camera + microphone) wakati wa kuaccept.

## 6. Checklist ya kipimo

- [ ] `flutter analyze` → No issues found
- [ ] `flutter test` → 13/13
- [ ] Chat → kitufe cha simu → invitation inatoka → simu inapokea → pande zote zinazungumza (voice)
- [ ] Kitufe cha video → pande zote zinaonana
- [ ] App iko background → notification inaibuka na kuringa → ita kwenye app
- [ ] App imefungwa (killed) → FCM + ZEGO offline push → ringtone
- [ ] App ina logout → Zego `uninit()` (halitumiki tena)
