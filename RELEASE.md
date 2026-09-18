# Kutengeneza Release APK — Pacific Dating App

## ⬇️ Pakua APK tayari (GitHub Release)

APK ya release ipo kwenye GitHub — hakuna haja ya kujenga mwenyewe:

**https://github.com/amran03/pacific-dating-app/releases/download/v1.0.0/Pacific-v1.0.0-release.apk**

| Kipimo | Thamani |
|---|---|
| Ukubwa | 87.47 MB |
| SHA-256 | `9da5188f3069f8bc705ce533b46dff8c5adb9cc11c77b86d473f70a0ca581d8f` |

Ukurasa wa release: https://github.com/amran03/pacific-dating-app/releases/tag/v1.0.0

Thibitisha faili uliyopakua:

```powershell
Get-FileHash .\Pacific-v1.0.0-release.apk -Algorithm SHA256
```

## Faili lililotengenezwa

```
build/app/outputs/flutter-apk/app-release.apk    (~87.5 MB)
```

| Kipimo | Thamani |
|---|---|
| Package | `com.example.pacific_dating_app` |
| Version | `1.0.0` (versionCode 1) |
| minSdk | 24 (Android 7.0) |
| targetSdk / compileSdk | 36 (Android 16) |
| Signature schemes | APK Signature Scheme v2 ✅ |
| Certificate DN | `CN=Pacific, OU=Mobile, O=Pacific, L=Dar es Salaam, ST=Dar es Salaam, C=TZ` |
| Certificate SHA-1 | `1C:31:86:34:DA:2F:6E:6C:59:33:19:E6:95:97:80:63:29:4E:66:8A` |
| Certificate SHA-256 | `c73c0e081d3e4eee2b07c931cb9fe6688f235d6981e195e9473f098edc58c7a1` |

## Amri ya kutengeneza

```bash
flutter build apk --release
```

Matokeo: `build/app/outputs/flutter-apk/app-release.apk`

Kwa Play Store tumia App Bundle badala yake:

```bash
flutter build appbundle --release
```

Matokeo: `build/app/outputs/bundle/release/app-release.aab`

## Mahitaji ya toolchain (muhimu)

Flutter 3.44.2 inalazimisha matoleo ya chini kabisa ya Gradle/AGP/Kotlin.
Mradi umesanidiwa hivi (`android/`):

| Kipengele | Toleo | Kwa nini |
|---|---|---|
| Gradle | 8.14.3 | Flutter inahitaji ≥ 8.14.0; Java 21 inahitaji ≥ 8.4 |
| Android Gradle Plugin | 8.11.1 | Flutter inahitaji ≥ 8.11.1 |
| Kotlin Gradle Plugin | 2.2.20 | Flutter inahitaji ≥ 2.2.20 |
| Java (JDK) | 17–21 | Gradle 8.x haiwiani na Java 25 |

### Kuweka JDK inayofaa

Kama `flutter doctor` inaonyesha Java 25 (Android Studio JBR ya sasa),
build itafeli. Tumia JDK 17 au 21:

```bash
flutter config --jdk-dir="C:\Users\<jina>\jdk21\jdk-21.0.12.1+1"
```

Kisha thibitisha:

```bash
flutter doctor -v
```

## Kusaini release kwa keystore yako mwenyewe

Sasa mradi unasoma `android/key.properties` ikiwepo; kama haipo inarudi
kwenye debug keystore ili build isifeli.

### 1. Tengeneza keystore

```bash
keytool -genkeypair -v -keystore android/app/upload-keystore.jks ^
  -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias upload
```

### 2. Tengeneza `android/key.properties`

```bash
cp android/key.properties.example android/key.properties
```

Kisha jaza:

```properties
storePassword=<password yako>
keyPassword=<password yako>
keyAlias=upload
storeFile=upload-keystore.jks
```

### 3. Build

```bash
flutter build apk --release
```

> ⚠️ **MUHIMU:** `android/key.properties` na faili zote `*.jks` / `*.keystore`
> hazipo kwenye git (`.gitignore`). Hifadhi keystore mahali salama —
> ukiipoteza hutaweza kutolea update kwenye Play Store kwa package hiyo hiyo.

## Kuweka App ID halisi (kabla ya kutoa Play Store)

`applicationId` ya sasa ni ya mfano: `com.example.pacific_dating_app`.
Badilisha kuwa domain yako, kwa mfano `com.pacific.dating`:

1. `android/app/build.gradle.kts` → `namespace` na `applicationId`
2. Rebuild: `flutter clean && flutter build apk --release`

> Kumbuka: ukibadilisha `applicationId` baada ya kutolea Play Store,
> unatengeneza app mpya kabisa yenye signature mpya. Badilisha KABLA ya kutoa.

## Kuthibitisha APK

```bash
"C:\Users\DELL\AppData\Local\Android\sdk\build-tools\36.0.0\apksigner.bat" ^
  verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
```

Lazima ionyeshe `Verifies` na `EXITCODE=0`.

## Kuendesha majaribio

```bash
flutter test
```

Majaribio yote yanapita (`test/pesapal_service_test.dart`,
`test/widget_test.dart`).

## Kuweka kwenye Simu (sideload)

```bash
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Au hamisha faili `app-release.apk` kwenye simu na uifungue
(unahitaji kuruhusu "Install unknown apps").