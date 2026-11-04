# Auto patrol

Upload `firmware/FireGuardBLE/FireGuardBLE.ino` to the ESP32 and use the Flutter app from this package. Connect under **Devices**, wait for the STOP confirmation, then select **Control → Auto**. Keep the app in the foreground and connected. Press **STOP** to return to Manual.

## What the robot does

1. With no flame and a valid clear front distance, drive forward.
2. At 25 cm or closer, stop forward movement and make short right turns with pauses to check the front sensor. Resume forward patrol when clearance reaches 30 cm. A missing echo stops movement until a valid reading returns.
3. A flame interrupts patrol. Turn toward a single left/right detection when front clearance exceeds 25 cm. If both side sensors detect a flame without the center sensor, stop because the direction is unclear. With insufficient or unknown front clearance, stay stopped rather than align.
4. When the center flame sensor detects a flame, stop the motors, switch on the pump, and sweep the nozzle between 60° and 120°. Spraying is stationary and does not require a distance reading.
5. When no flame sensor detects a flame, turn the pump off and remain stopped for 1.5 seconds. If the sensors remain clear, resume patrol. A fresh flame detection interrupts this waiting period.

The robot does not drive toward a detected flame or reverse automatically. The existing 1.2-second command watchdog, disconnect stop, manual controls, GPIO wiring, and motor direction calibration remain in place. Turning the phone screen off/backgrounding the app stops the robot.

## Adjusting behavior

The constants near the top of the sketch control patrol:

| Constant | Default | Purpose |
| --- | --- | --- |
| `AUTO_OBSTACLE_CM` | 25 | Enter obstacle avoidance at or below this front distance |
| `AUTO_CLEAR_CM` | 30 | Resume forward patrol at or above this distance |
| `AUTO_MAX_SPEED` | 150 | Auto PWM cap out of 255; a lower app speed is respected |
| `AUTO_TURN_ACTIVE_MS` | 350 | Right-turn request duration, including 100 ms motor interlock |
| `AUTO_TURN_CYCLE_MS` | 650 | Full turn-and-pause cycle |
| `AUTO_FLAME_CLEAR_MS` | 1500 | Clear-flame interval required before restarting patrol |

Keep the clear threshold above the obstacle threshold and leave a stationary pause in each turn cycle. Thresholds and speed need checking on the actual chassis: stopping distance and turning clearance depend on the motors, floor, weight and sensor mounting.

## Hardware check

First test with the drive wheels raised and pump power disconnected: confirm forward/right/left directions, the active-LOW flame readings and relay behavior, and STOP/link-loss operation. Then check low-speed obstacle handling in a clear, supervised space. One front ultrasonic sensor cannot detect side/rear obstacles, drop-offs or all surfaces; ensure clearance for the turning footprint. Use the physical power cutoff if needed. This prototype is not a fire-safety system.

Firmware host simulation: `bash firmware/tests/run.sh`. These checks exercise the logic; they do not establish physical stopping distances, flame sensor accuracy or real BLE delivery. See `VALIDATION.md` for the checks actually completed.
