import 'dart:convert';
import 'dart:io';

import 'package:fireguard/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android options match the registered native app configuration', () {
    final native =
        jsonDecode(File('android/app/google-services.json').readAsStringSync())
            as Map<String, dynamic>;
    final client = (native['client'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (client) =>
              client['client_info']['android_client_info']['package_name'] ==
              'com.fireguard.fireguard',
        );
    const options = DefaultFirebaseOptions.android;
    expect(options.projectId, 'fireguard-d6283');
    expect(options.projectId, native['project_info']['project_id']);
    expect(options.messagingSenderId, native['project_info']['project_number']);
    expect(options.appId, client['client_info']['mobilesdk_app_id']);
    expect(options.apiKey, client['api_key'][0]['current_key']);
  });

  test('iOS options match the bundled Firebase plist', () {
    final xml = File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
    String? value(String key) => RegExp(
      '<key>$key</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(xml)?.group(1);
    const options = DefaultFirebaseOptions.ios;
    expect(options.projectId, 'fireguard-d6283');
    expect(options.projectId, value('PROJECT_ID'));
    expect(options.appId, value('GOOGLE_APP_ID'));
    expect(options.apiKey, value('API_KEY'));
    expect(options.messagingSenderId, value('GCM_SENDER_ID'));
    expect(options.iosBundleId, value('BUNDLE_ID'));
  });

  test('Each supported native platform selects its registered app', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      DefaultFirebaseOptions.currentPlatform,
      DefaultFirebaseOptions.android,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(DefaultFirebaseOptions.currentPlatform, DefaultFirebaseOptions.ios);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      () => DefaultFirebaseOptions.currentPlatform,
      throwsUnsupportedError,
    );
    expect(DefaultFirebaseOptions.web.projectId, 'fireguard-d6283');
    expect(
      DefaultFirebaseOptions.web.appId,
      '1:384241337823:web:3828a222c90e55b5f4f06a',
    );
  });
}
