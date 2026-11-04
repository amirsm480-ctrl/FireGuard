// Generated from the registered Firebase app SDK configurations on 2026-11-04.
// These are client SDK identifiers; no account credentials are included.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError('FireGuard supports Android, iOS and web.'),
    };
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBMowG5Awodh9z-V1aMezAGIpbXtDy8rls',
    appId: '1:384241337823:web:3828a222c90e55b5f4f06a',
    messagingSenderId: '384241337823',
    projectId: 'fireguard-d6283',
    authDomain: 'fireguard-d6283.firebaseapp.com',
    storageBucket: 'fireguard-d6283.firebasestorage.app',
    measurementId: 'G-1XNBWYG97G',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAS0P-T3HigZCcht4PpHFFPfnw0nQWSqPM',
    appId: '1:384241337823:android:ea7c89b851055a7bf4f06a',
    messagingSenderId: '384241337823',
    projectId: 'fireguard-d6283',
    storageBucket: 'fireguard-d6283.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDG6ccI1D5qIk-SEAPz2-LGQRPgyRgBEs4',
    appId: '1:384241337823:ios:520be702f0ecd3e8f4f06a',
    messagingSenderId: '384241337823',
    projectId: 'fireguard-d6283',
    storageBucket: 'fireguard-d6283.firebasestorage.app',
    iosBundleId: 'com.fireguard.fireguard',
  );
}
