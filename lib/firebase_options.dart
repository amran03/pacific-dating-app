import 'package:firebase_core/firebase_core.dart'
    show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

// ============================================================
// FIREBASE OPTIONS — KU ZA FIRST LAUNCH
// ============================================================
//
// MUHIMU: File hii ni KWAJIBA kwa Firebase.initializeApp() ili ishiriki
// na project yako. Muundo wangu ni wa flutterfire CLI (inawafanya
// kiotomatiki).
//
// KU KU-FILL:
//   1. Weka lib/firebase_options.dart
//   2. Ingeza "Project settings > General > Your apps > Web" kwenye
//      Firebase Console.
//   3. Kupaia na VALUES YA PROJECT WAKO HALISI kwenye apiKey/appId/zote
//      hapa. Haziweze kuweka placeholders hivi bila values za sahihi.
//
// Mfano za weka values (kutoka Firebase Console):
//   apiKey:            'AIzaSy...'
//   appId:             '1:1234567890:web:abcdef'
//   messagingSenderId: '1234567890'
//   projectId:         'my-pacific-dating-app'
//   storageBucket:     'my-pacific-dating-app.appspot.com'
//
// KU WEWE (Android/iOS), databaseURL (Toola lu ikiwa jaribu):
// ============================================================

/// Default [FirebaseOptions] for Pacific Dating App.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      // TODO(Lyokone): Remove when FlutterFire CLI updated
      case TargetPlatform.windows:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: 'YOUR_FIREBASE_APP_ID',
    messagingSenderId: 'YOUR_FIREBASE_SENDER_ID',
    projectId: 'YOUR_FIREBASE_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: 'YOUR_FIREBASE_APP_ID_ANDROID',
    messagingSenderId: 'YOUR_FIREBASE_SENDER_ID',
    projectId: 'YOUR_FIREBASE_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    androidClientId: 'YOUR_ANDROID_CLIENT_ID',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: 'YOUR_FIREBASE_APP_ID_IOS',
    messagingSenderId: 'YOUR_FIREBASE_SENDER_ID',
    projectId: 'YOUR_FIREBASE_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosClientId: 'YOUR_IOS_CLIENT_ID',
    iosBundleId: 'YOUR_IOS_BUNDLE_ID',
  );

  static final FirebaseOptions macos = ios;
}