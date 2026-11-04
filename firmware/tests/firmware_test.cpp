#include <cassert>
#include <iostream>
#include "../FireGuardBLE/FireGuardBLE.ino"

RobotCommandCallbacks commandCallbacks;
BLECharacteristic commandChar;
uint8_t nextSequence = 1;

void runLoop() {
  loop();
  // Automatic spraying must never energize the drive motors.
  if (modeAuto && pumpActive) {
    assert(activeMotion == STOP);
    assert(duty[PWM_MOTOR_A] == 0 && duty[PWM_MOTOR_B] == 0);
  }
}

void connectController(uint16_t id = 1) {
  esp_ble_gatts_cb_param_t event{};
  event.connect.conn_id = id;
  bleServer->callbacks->onConnect(bleServer, &event);
  runLoop();
}

void disconnectController(uint16_t id = 1) {
  esp_ble_gatts_cb_param_t event{};
  event.disconnect.conn_id = id;
  bleServer->callbacks->onDisconnect(bleServer, &event);
  runLoop();
}

void command(uint8_t mode = 0, uint8_t direction = 0, uint8_t pump = 0,
             uint8_t angle = 90, uint8_t version = 1, uint16_t id = 1,
             uint8_t speed = 150) {
  uint8_t bytes[] = {version, nextSequence++, mode, direction, speed, angle, pump, 0};
  commandChar.setValue(bytes, sizeof(bytes));
  esp_ble_gatts_cb_param_t event{};
  event.write.conn_id = id;
  static_cast<BLECharacteristicCallbacks&>(commandCallbacks).onWrite(&commandChar, &event);
}

void advance(uint32_t ms) {
  simulatedTime += ms;
  runLoop();
}

void autoCommand(uint8_t speed = 220) {
  command(1, 0, 0, 90, 1, 1, speed);
}

// Keep the BLE command stream alive while exercising timed auto behavior.
void advanceAuto(uint32_t duration, uint8_t speed = 220) {
  const uint32_t started = millis();
  while (millis() - started < duration) {
    const uint32_t remaining = duration - (millis() - started);
    autoCommand(speed);
    advance(std::min<uint32_t>(25, remaining));
  }
}

void setDistance(float cm) {
  echoPulse = cm < 0 ? 0 : static_cast<unsigned long>(cm * 2.0f / 0.0343f + 0.5f);
}

void sampleAutoDistance(float cm) {
  setDistance(cm);
  autoCommand();
  advance(101);
}

void flames(bool left, bool center, bool right) {
  gpio[FLAME_LEFT] = left ? LOW : HIGH;
  gpio[FLAME_CENTER] = center ? LOW : HIGH;
  gpio[FLAME_RIGHT] = right ? LOW : HIGH;
}

void freshController() {
  if (linkConnected) disconnectController();
  flames(false, false, false);
  setDistance(100);
  advance(101);
  connectController();
  command();
  runLoop();
  assert(hasCommand && !watchdogTripped && !requireStopCommand);
  assert(!modeAuto && activeMotion == STOP && !pumpActive);
}

void testManualAndProtocol() {
  connectController();
  command(1);
  runLoop();
  assert(!modeAuto); // A stop handshake is required first.
  command();
  runLoop();
  assert(hasCommand && !watchdogTripped && !requireStopCommand);
  command(0, 1);
  runLoop();
  advance(110);
  assert(activeMotion == FORWARD);
  assert(gpio[IN1] == HIGH && gpio[IN2] == LOW && gpio[IN3] == HIGH && gpio[IN4] == LOW);
  command(0, 3);
  runLoop();
  assert(activeMotion == STOP);
  advance(110);
  assert(activeMotion == LEFT);
  assert(gpio[IN1] == LOW && gpio[IN2] == HIGH && gpio[IN3] == HIGH && gpio[IN4] == LOW);
  setDistance(8);
  command(0, 1);
  advance(110);
  assert(activeMotion == STOP && statusCode == FORWARD_BLOCKED);
  setDistance(-1);
  command(0, 1);
  advance(110);
  advance(110);
  assert(distanceCm < 0 && activeMotion == FORWARD); // Manual no-echo behavior is retained.
  command(0, 0, 1, 120);
  runLoop();
  assert(pumpActive && servoAngle == 120);
  command(2);
  command(0, 1, 1); // Emergency STOP cannot be overwritten by later movement.
  runLoop();
  assert(activeMotion == STOP && !pumpActive && !modeAuto && servoAngle == 90);
  const auto accepted = ackSequence;
  command(0, 1, 0, 90, 9);
  runLoop();
  assert(ackSequence == accepted);
  command(0, 1, 0, 90, 1, 2);
  runLoop();
  assert(ackSequence == accepted); // A different peer cannot control the robot.
  command(1, 1);
  runLoop();
  assert(ackSequence == accepted); // AUTO cannot carry a manual direction.

  const uint8_t malformed[][8] = {
    {1, 240, 0, 5, 150, 90, 0, 0},
    {1, 241, 0, 0, 150, 181, 0, 0},
    {1, 242, 0, 0, 150, 90, 2, 0},
    {1, 243, 0, 0, 150, 90, 0, 1},
    {1, 244, 3, 0, 150, 90, 0, 0},
  };
  esp_ble_gatts_cb_param_t event{};
  event.write.conn_id = 1;
  for (const auto& invalid : malformed) {
    uint8_t bytes[8];
    memcpy(bytes, invalid, sizeof(bytes));
    commandChar.setValue(bytes, sizeof(bytes));
    static_cast<BLECharacteristicCallbacks&>(commandCallbacks).onWrite(&commandChar, &event);
    runLoop();
    assert(ackSequence == accepted);
  }
  uint8_t shortPacket[] = {1, 245, 0};
  commandChar.setValue(shortPacket, sizeof(shortPacket));
  static_cast<BLECharacteristicCallbacks&>(commandCallbacks).onWrite(&commandChar, &event);
  runLoop();
  assert(ackSequence == accepted);
}

void testPatrolAndSpeed() {
  freshController();
  autoCommand();
  runLoop();
  assert(modeAuto && activeMotion == STOP && !pumpActive && statusCode == PATROLLING);
  advanceAuto(120);
  assert(activeMotion == FORWARD && !pumpActive);
  assert(motorSpeed == 220); // Telemetry retains the user's configured speed.
  assert(duty[PWM_MOTOR_A] == 150 && duty[PWM_MOTOR_B] == 150);
  advanceAuto(1300); // Repeated AUTO heartbeats must keep patrol running.
  assert(activeMotion == FORWARD && !watchdogTripped);
  advanceAuto(120, 95);
  assert(duty[PWM_MOTOR_A] == 95 && duty[PWM_MOTOR_B] == 95);
  advanceAuto(50, 0);
  assert(activeMotion == STOP && duty[PWM_MOTOR_A] == 0 && duty[PWM_MOTOR_B] == 0);
  command(0, 1, 0, 90, 1, 1, 220);
  runLoop();
  advance(110);
  assert(!modeAuto && activeMotion == FORWARD);
  assert(duty[PWM_MOTOR_A] == 220 && duty[PWM_MOTOR_B] == 220);
}

void testObstacleHysteresisAndPulses() {
  freshController();
  advanceAuto(150);
  assert(activeMotion == FORWARD);
  sampleAutoDistance(24);
  assert(activeMotion == STOP && !pumpActive && statusCode == AVOIDING);
  advanceAuto(140);
  assert(activeMotion == RIGHT && !pumpActive);
  advanceAuto(240); // Past the 350 ms turn window.
  assert(activeMotion == STOP && statusCode == AVOIDING);
  advanceAuto(400); // A second turn must occur despite repeated AUTO heartbeats.
  assert(activeMotion == RIGHT && statusCode == AVOIDING);
  sampleAutoDistance(28);
  assert(statusCode == AVOIDING && activeMotion != FORWARD); // Still below 30 cm clear threshold.
  advanceAuto(700);
  assert(statusCode == AVOIDING && activeMotion != FORWARD);
  sampleAutoDistance(31);
  assert(statusCode == PATROLLING && activeMotion == STOP);
  advanceAuto(120);
  assert(activeMotion == FORWARD);
  sampleAutoDistance(28); // The same reading is now clear enough to keep patrolling.
  assert(statusCode == PATROLLING && activeMotion == FORWARD);
}

void testUnknownDistance() {
  freshController();
  advanceAuto(150);
  sampleAutoDistance(-1);
  assert(modeAuto && activeMotion == STOP && !pumpActive && statusCode == DISTANCE_UNKNOWN);
  advanceAuto(1400);
  assert(activeMotion == STOP && !pumpActive && statusCode == DISTANCE_UNKNOWN);
  sampleAutoDistance(100);
  advanceAuto(120);
  assert(activeMotion == FORWARD && statusCode == PATROLLING);

  sampleAutoDistance(24);
  advanceAuto(390); // Avoidance is currently in its rest interval.
  assert(activeMotion == STOP && statusCode == AVOIDING);
  sampleAutoDistance(-1);
  assert(activeMotion == STOP && statusCode == DISTANCE_UNKNOWN);
  sampleAutoDistance(24);
  advanceAuto(140); // Valid range starts a fresh turn cycle.
  assert(activeMotion == RIGHT && statusCode == AVOIDING);
}

void testFlameInterruptsAndAlignment() {
  freshController();
  autoCommand();
  runLoop(); // Patrol is pending but has not begun moving.
  flames(false, true, false);
  runLoop();
  assert(activeMotion == STOP && pumpActive && statusCode == SPRAYING);
  advanceAuto(180);
  assert(activeMotion == STOP && pumpActive); // Pending forward motion was cancelled.
  assert(servoAngle >= 60 && servoAngle <= 120);

  freshController();
  advanceAuto(150);
  flames(true, false, false);
  runLoop();
  assert(activeMotion == STOP && !pumpActive); // Flame interrupts active patrol immediately.
  advanceAuto(120);
  assert(activeMotion == LEFT && !pumpActive);
  flames(false, false, true);
  runLoop();
  assert(activeMotion == STOP);
  advanceAuto(120);
  assert(activeMotion == RIGHT && !pumpActive);
  flames(true, false, true);
  runLoop();
  assert(activeMotion == STOP && !pumpActive && statusCode == UNCLEAR);
  flames(true, false, false);
  sampleAutoDistance(24);
  advanceAuto(120);
  assert(activeMotion == STOP && !pumpActive && statusCode == OBSTACLE);
  sampleAutoDistance(-1);
  advanceAuto(120);
  assert(activeMotion == STOP && !pumpActive && statusCode == DISTANCE_UNKNOWN);
  flames(false, true, false);
  runLoop();
  assert(activeMotion == STOP && pumpActive && statusCode == SPRAYING); // Center flame sprays without echo.
  advanceAuto(1300);
  assert(activeMotion == STOP && pumpActive && !watchdogTripped);
  assert(servoAngle >= 60 && servoAngle <= 120);
}

void testFlameClearConfirmation() {
  freshController();
  flames(false, true, false);
  autoCommand();
  runLoop();
  assert(pumpActive);
  flames(false, false, false);
  runLoop();
  assert(activeMotion == STOP && !pumpActive && statusCode == FIRE_CHECK);
  advanceAuto(1000);
  assert(activeMotion == STOP && !pumpActive && statusCode == FIRE_CHECK);
  flames(false, true, false); // A renewed flame restarts the confirmation interval.
  runLoop();
  assert(pumpActive && statusCode == SPRAYING);
  flames(false, false, false);
  runLoop();
  advanceAuto(1400);
  assert(activeMotion == STOP && !pumpActive && statusCode == FIRE_CHECK);
  advanceAuto(250);
  assert(activeMotion == FORWARD && !pumpActive && statusCode == PATROLLING);

  flames(true, false, false);
  runLoop();
  advanceAuto(120);
  assert(activeMotion == LEFT);
  flames(false, false, false);
  runLoop();
  advanceAuto(1400);
  assert(activeMotion == STOP && !pumpActive && statusCode == FIRE_CHECK);
  advanceAuto(250);
  assert(activeMotion == FORWARD && statusCode == PATROLLING);
}

void testStopWatchdogAndModeReset() {
  freshController();
  advanceAuto(150);
  command(2);
  autoCommand(); // AUTO cannot overwrite an unprocessed emergency STOP.
  runLoop();
  assert(!modeAuto && activeMotion == STOP && !pumpActive && servoAngle == 90);

  advanceAuto(150);
  assert(activeMotion == FORWARD);
  advance(1201);
  assert(!modeAuto && !pumpActive && activeMotion == STOP && watchdogTripped);
  autoCommand();
  runLoop();
  assert(!modeAuto && requireStopCommand);
  command();
  runLoop();
  advanceAuto(150);
  assert(modeAuto && activeMotion == FORWARD);
  disconnectController();
  assert(!modeAuto && !pumpActive && activeMotion == STOP);
  connectController();
  autoCommand();
  runLoop();
  assert(!modeAuto && activeMotion == STOP && requireStopCommand);
  command();
  runLoop();
  advanceAuto(150);
  assert(activeMotion == FORWARD);

  // A new AUTO session must not inherit avoidance hysteresis from the old one.
  sampleAutoDistance(24);
  assert(statusCode == AVOIDING);
  command();
  runLoop();
  setDistance(28);
  advance(101);
  advanceAuto(150);
  assert(activeMotion == FORWARD && statusCode == PATROLLING);

  // A new AUTO session must not inherit a flame-clear wait from the old one.
  flames(false, true, false);
  runLoop();
  assert(pumpActive);
  flames(false, false, false);
  runLoop();
  assert(statusCode == FIRE_CHECK);
  command();
  runLoop();
  advanceAuto(150);
  assert(activeMotion == FORWARD && !pumpActive && statusCode == PATROLLING);
  flames(false, true, false);
  runLoop();
  advance(1201);
  assert(!modeAuto && !pumpActive && activeMotion == STOP && watchdogTripped);

  freshController();
  flames(false, true, false);
  advanceAuto(120);
  assert(pumpActive);
  disconnectController();
  assert(!modeAuto && !pumpActive && activeMotion == STOP);
}

void testTelemetry() {
  freshController();
  advanceAuto(150);
  publishTelemetry();
  assert(telemetry->value.size() == 20);
  assert(static_cast<uint8_t>(telemetry->value[0]) == 1);
  assert(static_cast<uint8_t>(telemetry->value[1]) == ackSequence);
  assert(static_cast<uint8_t>(telemetry->value[4]) == 220);
  assert(static_cast<uint8_t>(telemetry->value[14]) == PATROLLING);
  sampleAutoDistance(-1);
  publishTelemetry();
  assert(static_cast<uint8_t>(telemetry->value[6]) == 255);
  assert(static_cast<uint8_t>(telemetry->value[7]) == 255);
  assert(static_cast<uint8_t>(telemetry->value[8]) == 144);
  assert(static_cast<uint8_t>(telemetry->value[9]) == 1);
  assert(static_cast<uint8_t>(telemetry->value[14]) == DISTANCE_UNKNOWN);
  for (int index = 15; index < 20; ++index) assert(telemetry->value[index] == 0);
}

int main() {
  setup();
  assert(activeMotion == STOP && !pumpActive && !modeAuto);
  testManualAndProtocol();
  testPatrolAndSpeed();
  testObstacleHysteresisAndPulses();
  testUnknownDistance();
  testFlameInterruptsAndAlignment();
  testFlameClearConfirmation();
  testStopWatchdogAndModeReset();
  testTelemetry();
  std::cout << "Firmware simulation passed: manual/protocol, patrol/speed, obstacle hysteresis/pulses, unknown range, flame interruption/alignment/spray, flame-clear confirmation, STOP/watchdog/disconnect/mode reset, and telemetry.\n";
}
