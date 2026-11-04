import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// BLE and demo remain available when cloud setup is missing or unavailable.
Future<String?> initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return null;
  } catch (_) {
    return 'Firebase is not configured or could not start. '
        'Follow docs/FIREBASE_SETUP.md.';
  }
}
