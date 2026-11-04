# FireGuard BLE protocol v1

The ESP32 is a BLE GATT peripheral named **FireGuard Robot**. The Flutter mobile app is the central/controller. The robot link uses no Wi-Fi hotspot, HTTP service, cloud account, or internet connection. Separately, the Flutter app uses Firebase over the phone or tablet’s internet connection to store history. BLE is compatible with the Android and iOS Core Bluetooth path used by the app, including iPad. This firmware targets the original ESP32 Dev Module / WROOM or SOLO pin arrangement in the supplied sketch.

## Service and characteristics

| Item | UUID | Properties |
| --- | --- | --- |
| Service | `7a1e0001-b5a3-f393-e0a9-e50e24dcca9e` | Advertised |
| Command | `7a1e0002-b5a3-f393-e0a9-e50e24dcca9e` | Write with response |
| Telemetry | `7a1e0003-b5a3-f393-e0a9-e50e24dcca9e` | Read, notify, CCCD |

Packets fit the default 23-byte ATT MTU. No MTU negotiation or message fragmentation is needed. Read telemetry after discovery and subscribe to notifications. Notifications are generated every 250ms. Send a complete command every 250ms while the app is active, even when the controls have not changed. Subscribe before sending the first command so the first telemetry acknowledgment can be observed.

## Commands: exactly 8 bytes

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint8 | Protocol version: `1` |
| 1 | uint8 | Sequence number, wraps after 255 |
| 2 | uint8 | Mode: `0` manual, `1` auto, `2` emergency stop |
| 3 | uint8 | Direction: `0` stop, `1` forward, `2` backward, `3` left, `4` right |
| 4 | uint8 | Motor PWM: 0–255 |
| 5 | uint8 | Manual nozzle angle: 0–180 degrees |
| 6 | uint8 | Manual pump: `0` off, `1` on |
| 7 | uint8 | Reserved; must be `0` |

AUTO and emergency stop packets must use direction `0`, angle `90` and pump `0`. AUTO computes the physical outputs from the sensors. Emergency stop ignores motor speed, forces MANUAL, disables the motor and pump, and centers the nozzle. The servo remains powered to hold center.

A new connection, or a tripped watchdog, requires a **stop handshake**: send MANUAL + direction `0` + angle `90` + pump `0`, or emergency stop. Wait for matching sequence telemetry with MANUAL/STOP/pump OFF before permitting active controls. The firmware ignores active commands before this handshake; reconnecting cannot resume the previous AUTO or movement state.

Examples in hexadecimal:

- Initial stop, sequence 1, motor speed 150: `01 01 00 00 96 5A 00 00`
- Forward, sequence 2, motor speed 150: `01 02 00 01 96 5A 00 00`
- Auto, sequence 3, motor speed 150: `01 03 01 00 96 5A 00 00`
- Emergency stop, sequence 4: `01 04 02 00 96 5A 00 00`

The ATT write response confirms receipt by the BLE stack, not execution. Byte 1 of telemetry acknowledges the last command processed by the robot loop. Invalid packets are ignored and do not update the application acknowledgment or refresh the watchdog. The byte sequence is an acknowledgment token, not an authentication or replay protection scheme.

## Telemetry: exactly 20 bytes

Multi-byte integers are little-endian.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint8 | Protocol version: `1` |
| 1 | uint8 | Last applied command sequence |
| 2 | uint8 | Flags, below |
| 3 | uint8 | Actual motor direction, command direction enumeration |
| 4 | uint8 | Configured motor PWM, 0–255 |
| 5 | uint8 | Actual nozzle angle in degrees |
| 6–7 | uint16 | Distance in tenths of a centimeter; `65535` means unavailable |
| 8–9 | uint16 | MQ2 raw ADC, 0–4095; **not ppm or AQI** |
| 10–13 | uint32 | ESP32 uptime in seconds |
| 14 | uint8 | Status code, below |
| 15–19 | bytes | Reserved, zero |

Flags: bit 0 AUTO; bit 1 pump energized; bit 2 left flame; bit 3 center flame; bit 4 right flame; bit 5 PWM initialized; bit 6 watchdog/link stop; bit 7 reserved.

| Status | Meaning |
| --- | --- |
| 0 | Stopped / idle |
| 1 | Moving or turning; actual direction is byte 3 |
| 2 | Forward movement blocked by valid distance under 15cm |
| 3 | AUTO searching |
| 4 | AUTO spraying |
| 5 | AUTO obstacle nearby |
| 6 | AUTO flame direction unclear |
| 7 | AUTO search rest interval |
| 8 | No healthy command stream / watchdog stop |
| 9 | PWM initialization failure; motor and pump disabled |
| 10 | AUTO patrolling forward, or waiting for the motor direction interlock |
| 11 | AUTO obstacle avoidance: turning right or pausing between turns |
| 12 | AUTO distance unavailable; movement stopped |
| 13 | AUTO waiting for flame sensors to remain clear before resuming patrol |

Status values 0–9 remain valid for stored history and older firmware. Values 10–13 extend the existing v1 telemetry frame without changing its size. Use the updated app with the patrol firmware; older app builds reject these new status values. Motor PWM byte 4 is the selected setting; physical Auto PWM is capped at 150.

## Connection and motion behavior

Only one controller connection is accepted. Advertising stops while it is connected and restarts after disconnection. The loop stops motors/pump when a disconnect is observed, or when no valid applied command has arrived for **1200ms in either mode**. A distance measurement may block the loop for up to 25ms. A stop handshake is required again after watchdog expiry. The phone must stop sending control heartbeats when backgrounded and request emergency stop before disconnecting.

The application maintains one serialized write stream. Holding an arrow sends that direction repeatedly; release sends direction STOP. Emergency stop must take priority over pending movement. The firmware mailbox latches a pending emergency stop so later commands cannot overwrite it before execution. All output changes run on the Arduino loop task; BLE callbacks only change a protected mailbox.

Motion and Auto patrol behavior:

- In MANUAL, only a valid distance below 15cm blocks forward movement. Unavailable echo retains the original manual behavior of permitting movement; it does not establish that the path is clear.
- Direction changes insert a 100ms motor stop.
- AUTO patrols forward while front distance is valid and clear. At 25cm or less it latches avoidance: a right-turn request for 350ms of each 650ms cycle, including the usual 100ms motor interlock, followed by a stationary sensor check. Forward patrol resumes only at 30cm or greater. It never reverses automatically.
- Unknown range stops autonomous movement and resets the turn cycle. Auto motor output is capped at 150/255, or the selected speed if lower; speed zero disables movement.
- Any flame cancels patrol and pending movement. A side flame turns the robot to align only with a valid front clearance over 25cm; conflicting side sensors stop it. Center flame detection stops motors and sprays even if range is unknown. AUTO does not drive forward toward fire.
- When all flame sensors clear, the pump stops immediately and the robot remains stationary for 1500ms of clear readings before resuming patrol. A renewed detection restarts this interval.
- The automatic nozzle sweeps 60–120 degrees in five-degree increments every 100ms during spraying.
- MQ2 provides raw monitoring only and does not trigger autonomous actuation.

Repeated AUTO heartbeats preserve the patrol/avoidance/flame state. STOP, manual mode, watchdog expiry and disconnection reset it. AUTO stops when the app command heartbeat is lost. All timers are nonblocking so command handling remains active.

This is basic front-obstacle handling, not mapping or full collision avoidance. The ultrasonic sensor cannot establish side/rear clearance or measure flame distance. See [Auto mode](AUTO_MODE.md) for setup and calibration.

## Pin mapping and electrical setup

| Function | GPIO |
| --- | --- |
| Left motor ENA / IN1 / IN2 | 33 / 13 / 14 |
| Right motor ENB / IN3 / IN4 | 25 / 27 / 26 |
| Left / center / right flame | 18 / 19 / 5, active LOW |
| Pump relay | 16, active LOW |
| Ultrasonic TRIG / ECHO | 17 / 32 |
| MQ2 analog input | 35 |
| SG90 servo signal | 22 |

Use the original appropriate voltage dividers for HC-SR04 ECHO and MQ2 analog output, and the separate regulated 5V servo supply with common ground. Pins 16/17 in this mapping are intended for WROOM/SOLO rather than WROVER. The BLE service currently has no bonding, PIN or owner authentication; operate this project with a supervised robot. Emergency stop in this app is a software command and requires a functioning connection; the firmware timeout is the fallback.

## Build and integration

Open `firmware/FireGuardBLE/FireGuardBLE.ino` in Arduino IDE. Select **ESP32 Dev Module** with the official Espressif Arduino ESP32 core and the default Bluedroid BLE stack. No separate servo, BluetoothSerial, NimBLE or ArduinoJson library is required. Use a flash partition with at least 1.5MB application space, such as **Huge APP (3MB No OTA/1MB SPIFFS)** if the default partition is too small. The source keeps the 2.x/3.x LEDC compatibility paths; the actual build verification is recorded in `docs/VALIDATION.md`. Run the portable logic checks with `bash firmware/tests/run.sh`; see `firmware/tests/README.md` for their scope.

Primary API references: [Espressif BLE server example](https://github.com/espressif/arduino-esp32/tree/3.3.12/libraries/BLE/examples/BLE_server), [Espressif Arduino LEDC API](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html).
