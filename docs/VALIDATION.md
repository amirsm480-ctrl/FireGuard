# Validation status

Completed on 3 November 2026:

- **19 Flutter tests passed** using `flutter test --no-pub --concurrency=1 --reporter expanded`.
- Protocol checks cover minimum-MTU frames, little-endian fields, unknown distance, malformed/out-of-range packets, emergency-stop encoding, and new patrol status codes through history storage.
- Controller checks cover STOP handshake, release, background stop, stale telemetry, late packets, STOP precedence over in-flight movement, missing command acknowledgements, and demo/cloud isolation.
- UI checks cover all four screens at widths 320, 390, 768, and 1024 logical pixels; 1.5x phone text; hold/release/cancel; and stopping outputs when leaving Control.
- Phone and tablet demo previews were rendered from the Flutter UI.
- Host C++ simulation against the actual ESP32 sketch passed watchdog, handshake, motor, pump, sensor, patrol, turn-cycle hysteresis, flame interruption/spraying, packet validation, and disconnect checks.
- `flutter build web --no-pub` completed successfully.

The earlier analyzer found UI syntax/lint issues that were corrected before the passing test run. A final clean analyzer result is not claimed. Android APK compilation, iOS signing, live BLE radio operation, and Firebase synchronization remain unverified.

No firmware was flashed and no Firebase project was created. Firebase configuration is the documented unconfigured stub. Use a physical ESP32/mobile device and your Firebase project for end-to-end verification.
