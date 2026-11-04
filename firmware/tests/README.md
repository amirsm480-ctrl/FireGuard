# Firmware host simulation

From the Flutter project folder, run:

```sh
bash firmware/tests/run.sh
```

Requires a C++17 compiler named `c++`. The script builds a temporary executable, runs it, and removes it. It directly includes the delivered `FireGuardBLE.ino`; the small headers under `stubs/` replace Arduino GPIO, time, PWM, and BLE APIs for deterministic testing.

The checks exercise:

- Stopped startup, the mandatory stop handshake, invalid packets, and wrong-controller writes.
- Calibrated manual motor outputs, the 100 ms direction-change pause, the 15 cm manual forward block, and retained manual unknown-echo behavior.
- Manual pump/nozzle control and emergency-stop priority over later pending commands.
- Automatic forward patrol, a 150 PWM cap that preserves lower requested speeds, zero-speed stop, and restoration of the configured speed in Manual.
- Obstacle avoidance with a 25 cm entry threshold, 30 cm clear threshold, and repeated right-turn/rest cycles that survive incoming AUTO heartbeats.
- Automatic stop on unknown range, recovery when range returns, and restart of the avoidance cycle after a missing echo.
- Flame interruption of both active and pending patrol, left/right alignment, ambiguous flame direction, and alignment blocked by nearby obstacles or unknown range.
- Center-flame spraying even when distance is unavailable, bounded nozzle sweep, and no simultaneous automatic pumping and motor drive.
- A 1.5-second flame-clear confirmation before patrol resumes; a renewed flame restarts the wait.
- Emergency STOP, watchdog expiry, disconnect, reconnect handshake, and clearing automatic state when leaving/re-entering Auto.
- Telemetry frame size/version, acknowledgment, configured speed, sensor fields, new automatic statuses, and unknown-distance encoding.

Timed behavior runs with repeated AUTO commands to model a healthy controller heartbeat. Watchdog checks deliberately stop that stream. Sensor changes use the simulated ultrasonic echo and active-LOW flame pins.

This is a sequential logic simulation. It does not validate radio delivery, FreeRTOS task scheduling, real electrical behavior, servo limits, sensor calibration, or the mobile Bluetooth stack. The actual ESP32 compiler check and an end-to-end hardware test remain separate checks.

To compile with the Arduino CLI and installed Espressif board package:

```sh
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app firmware/FireGuardBLE
```

In Arduino IDE select **ESP32 Dev Module** and **Huge APP (3MB No OTA/1MB SPIFFS)**. No upload is performed by these tests.
