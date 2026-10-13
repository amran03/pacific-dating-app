import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config inasomwa kutoka android/key.properties (haipo kwenye git).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.pacific_dating_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.pacific_dating_app"

        // ZEGO inahitaji minSdk >= 21; kama Flutter iko chini ya 21, tumia 21.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // ZEGO keep-rules — kama R8/minify itawashwa siku tofauti, zipo tayari.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Signing: tumia release keystore kama ipo, vinginevyo debug keys
            // ili `flutter build apk --release` isifeli kwenye mashine isiyo na keystore.
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ============================================================
// FCM (firebase_messaging + ZEGO offline call invitations).
// Inaapplywa TU google-services.json ipo — bila fail ya json,
// build itabaki salama (kama ilivyokuwa kabla).
// Pakua json kutoka: Firebase Console > Project settings > Android app.
// ============================================================
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    // Required by flutter_local_notifications (core library desugaring).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Multidex - inahitajika kwa sababu multiDexEnabled = true
    implementation("androidx.multidex:multidex:2.0.1")
}