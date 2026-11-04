# FireGuard

A Flutter companion app for an ESP32 Dev Module firefighter robot. The app controls the robot over Bluetooth Low Energy and stores real telemetry and activity in Firebase Cloud Firestore. The ESP32 does not run a Wi-Fi hotspot.

All UI text, source identifiers, comments, and project documentation are in English.

## Included

- Responsive phone, iPhone, and iPad UI with a light dashboard, robot illustration, sensor cards, and MQ2 trend.
- Overview, Control, History, and Devices screens.
- BLE scanning, connection, a confirmed STOP handshake, live telemetry, and connection errors.
- Hold-to-move directional control, manual/auto mode, motor speed, pump, nozzle angle, and a prominent software STOP.
- Auto patrol with front-obstacle turns, flame alignment, stationary spraying, and a pause before patrolling again.
- Companion ESP32 BLE firmware retaining your original wiring and motor calibration.
- Firebase Authentication and Cloud Firestore integration, scoped security rules, and setup instructions.
- An explicitly labeled interactive demo that never sends robot commands or saves demo data to Firebase.

## Run the app

Requirements: Flutter stable with Dart 3.10 or later, Android SDK for Android; macOS and Xcode for iPhone/iPad builds. The supplied platform settings target Android 7.0/API 24 or later and iOS/iPadOS 15 or later. BLE requires a physical Android or Apple device for end-to-end testing.

```sh
flutter pub get
flutter run
```

Use **Devices → Explore demo** to explore the interface without a robot. A browser preview can also run with `flutter run -d chrome`; browser BLE is intentionally unavailable.

### Open the browser preview on a laptop

Build with `flutter build web`, then serve the project's `build/web` folder from the project directory:

```sh
python3 -m http.server --directory build/web 8000
```

Open `http://localhost:8000` and choose **Devices → Explore demo**. The browser preview simulates the robot; connecting to or controlling the real robot requires the native Android or iPhone app.

To produce an Android development APK:

```sh
flutter build apk --debug
```

To run on iPad, open this project on a Mac, configure the signing team for `ios/Runner.xcworkspace` in Xcode, then run on the connected iPad. Layouts adapt to portrait, landscape, and narrow window sizes; no orientation is locked. A signed iOS build cannot be generated on Linux. Release signing and App Store submission are not configured.

## Connect Firebase

Follow [the Firebase setup guide](docs/FIREBASE_SETUP.md). No Firebase project or account is bundled. Until you complete that setup, the app honestly shows **Firebase not configured**; live BLE control and demo remain usable.

```text
ESP32 Dev Module ← BLE → Flutter app ← internet → Firebase
```

Firebase stores history; motor control stays on the direct BLE connection. The phone/iPad can use normal Wi-Fi or cellular data for Firebase.

## Install the robot firmware

1. Open `firmware/FireGuardBLE/FireGuardBLE.ino` in Arduino IDE.
2. Install the **esp32 by Espressif Systems** board package. Select **ESP32 Dev Module**, **Huge APP (3MB No OTA/1MB SPIFFS)** under Partition Scheme, and the correct USB port.
3. Upload the sketch. This replaces the old Wi-Fi dashboard firmware.
4. Open the native app, enable Bluetooth, allow the requested permissions, and scan under **Devices**.
5. Select **FireGuard Robot**. Controls unlock after the robot confirms it is stopped.
6. Open **Control → Auto** to start patrol. Keep the app open and connected. **STOP** returns to Manual.

Use the app and firmware from this ZIP together: the updated app recognizes the new patrol status messages. See [Auto mode](docs/AUTO_MODE.md) for behavior and adjustable firmware constants.

The firmware uses the ESP32's built-in BLE support; no HC-05 or other Bluetooth module is needed. It targets the classic ESP32 Dev Module/WROOM-style board and the exact pins from your source, not every board sold under the ESP family.

| Component | GPIO |
| --- | --- |
| Left motor ENA / IN1 / IN2 | 33 / 13 / 14 |
| Right motor ENB / IN3 / IN4 | 25 / 27 / 26 |
| Flame left / center / right | 18 / 19 / 5 |
| Ultrasonic TRIG / ECHO | 17 / 32 |
| MQ2 analog output | 35 |
| Servo signal | 22 |
| Pump relay, active LOW | 16 |

Preserve the original voltage dividers on HC-SR04 ECHO and MQ2 analog output. Power the servo from the existing 5 V buck converter with a common ground. Check the active-LOW relay behavior with the pump disconnected before a powered test.

## Behavior

- Manual movement lasts only while a direction is held. Releasing/canceling the touch sends STOP.
- In MANUAL, a valid ultrasonic distance below 15 cm blocks forward movement. Unknown distance is shown as unavailable and retains the original manual behavior of allowing forward movement.
- AUTO patrols forward with a valid clear front distance. At 25 cm or closer it stops, then turns right in short bursts until the front clearance reaches 30 cm. Unknown distance stops autonomous movement. Motor PWM in Auto is limited to 150/255, or the selected speed if lower.
- Any flame detection interrupts patrol. With front clearance over 25 cm, a side flame turns the robot to face it; a center flame stops the motors and runs the pump/nozzle sweep. It does not drive forward toward a flame. Once all flame sensors clear, the pump stops and the robot waits 1.5 seconds before resuming patrol.
- MQ2 values are raw 12-bit ADC readings (0–4095), not ppm, AQI, or a calibrated gas concentration.
- BLE disconnect, a 1.2-second command timeout, or app backgrounding stops both manual and automatic operation. Reconnection starts stopped; the app never resumes previous movement automatically.
- The software STOP resets manual mode, motor, pump, and nozzle. The servo remains powered to hold its centered position.

The BLE firmware is a nearby prototype controller and does not implement authenticated BLE bonding. Operate in a controlled setting with one controller. This software stop depends on the running electronics; retain a physical power cutoff for robot testing.

Obstacle handling uses one front ultrasonic sensor. It cannot detect side/rear obstacles, drop-offs, or every surface; confirm clearance for the robot's turning footprint and calibrate the distances and speed on your hardware. It is a supervised prototype, not a fire-safety system.

## Code map

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App startup |
| `lib/fireguard_app.dart`, `lib/ui/` | Theme, navigation, responsive screens |
| `lib/app_controller.dart` | Control state, heartbeat, lifecycle, demo |
| `lib/domain.dart` | Telemetry, command packet encoding/decoding |
| `lib/services/robot_transport.dart` | Native BLE transport and permissions |
| `lib/services/history_repository.dart` | Firebase history and CSV export |
| `lib/firebase_options.dart` | Stub replaced by FlutterFire configuration |
| `firestore.rules` | Per-user database access |
| `firmware/FireGuardBLE/` | ESP32 sketch |
| `docs/PROTOCOL.md` | BLE packet and watchdog specification |

## Validate

```sh
flutter analyze
flutter test
flutter build web
```

See [validation results](docs/VALIDATION.md) for checks completed in this environment and the hardware/cloud checks that still require your devices and Firebase project.
