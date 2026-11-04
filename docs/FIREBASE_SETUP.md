# Connect FireGuard to your Firebase project

This source includes the Firebase integration, but no live Firebase project has been created or connected. Until setup is complete, the app displays **Firebase not configured**. BLE control works independently. Demo data is never uploaded.

## 1. Create your project

Open https://console.firebase.google.com/ with your own Google account and create a project, for example **FireGuard Robot**. Choose your own unique project ID. Analytics is optional for this app.

Under **Build → Authentication → Get started → Sign-in method**, enable **Anonymous** authentication.

Under **Build → Firestore Database**, create the default Cloud Firestore database in **production mode**. Choose a suitable region before creating it. This project uses Firestore, not Realtime Database.

## 2. Register the Flutter apps

Install the Firebase CLI using the official instructions at https://firebase.google.com/docs/cli and sign in:

```sh
firebase login
dart pub global activate flutterfire_cli
```

From the FireGuard project folder:

```sh
flutter pub get
flutterfire configure --project=YOUR_PROJECT_ID --platforms=android,ios,web
```

Allow FlutterFire to replace `lib/firebase_options.dart`. The supplied file is deliberately an unconfigured stub, so the project can run without invented credentials. FlutterFire generates your actual platform configuration.

The Android application ID and iOS bundle ID are both `com.fireguard.fireguard`. Keep these matching the apps registered in Firebase. Web is only a UI/demo preview; robot BLE uses the native Android or iOS app.

If your shell cannot find `flutterfire`, add Dart's pub global executable directory to PATH as directed by the installation output. Do not put a service-account private key inside the Flutter app.

## 3. Publish the database rules

From the same folder:

```sh
firebase deploy --only firestore:rules,firestore:indexes --project=YOUR_PROJECT_ID
```

Alternatively, paste `firestore.rules` into Firestore's **Rules** tab and publish it. The app uses anonymous Firebase Authentication, with each installation restricted to its own user ID. Unauthenticated clients and other users cannot read or write that user's history.

## 4. Run and verify

```sh
flutter run
```

Connect the real BLE robot from **Devices**. After the app receives telemetry, inspect:

```text
users/{anonymousUserId}
  lastRobotId
users/{anonymousUserId}/robots/{encodedBluetoothId}/samples/{sampleId}
users/{anonymousUserId}/robots/{encodedBluetoothId}/events/{eventId}
```

The app queues a sensor snapshot every five seconds and on a state change. Activity entries record state transitions. The live chart keeps up to 60 samples; history loads up to 100 events; CSV export reads up to the latest 1,000 saved samples. The displayed session count is not the total number of documents in your database.

On Android and iOS, Firestore's offline cache queues writes after initial authentication. The app indicates pending synchronization. Internet is needed for first-time anonymous sign-in and cloud synchronization; ESP32 only uses Bluetooth. Your phone can use cellular data or a normal Wi-Fi connection while controlling the robot over BLE.

## Account behavior

Anonymous authentication is a simple starting point for this project. The same installation retains its identity across ordinary restarts. A separate phone or iPad gets a separate anonymous identity and separate history. Reinstalling or clearing app data may lose access to that identity. To share history across devices or recover an account, add a permanent sign-in provider and link the anonymous account before uninstalling. Account linking is not included in this version.

## Troubleshooting

- **Firebase not configured:** run `flutterfire configure` and restart the app completely.
- **Authentication unavailable:** enable Anonymous sign-in and check the phone's internet connection.
- **Write failed / permission denied:** deploy the supplied rules to the same Firebase project as the generated options.
- **Pending sync:** keep the app open with internet access and check Firebase Console; pending does not mean server-confirmed.
- **No demo documents:** expected. Demo telemetry is deliberately kept in memory.

Official references: [Flutter setup](https://firebase.google.com/docs/flutter/setup), [anonymous authentication](https://firebase.google.com/docs/auth/flutter/anonymous-auth), [offline persistence](https://firebase.google.com/docs/firestore/manage-data/enable-offline).
