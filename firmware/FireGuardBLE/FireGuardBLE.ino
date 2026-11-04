// FireGuard BLE • ESP32 Dev Module (WROOM/SOLO), Arduino-ESP32 2.x/3.x.
// Pin mapping and motor calibration preserved from the supplied robot sketch.
// No Wi-Fi / HTTP server. Use BLE GATT from the FireGuard Flutter app.
// Both MANUAL and AUTO stop after 1.2 seconds without valid commands.
// GPIO16/17 are unsuitable for WROVER modules. ECHO32 / MQ2 AO35 require
// suitable voltage dividers; ESP32 inputs are not 5V tolerant.
// Servo uses separate regulated 5V supply with common ground.
#include <Arduino.h>
#include <cstring>
#include <esp_arduino_version.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#if !defined(CONFIG_BLUEDROID_ENABLED)
#error "Select the classic ESP32 Dev Module with its default Bluedroid BLE stack."
#endif

// ===== MOTOR A: LEFT =====
const int ENA = 33;
const int IN1 = 13;
const int IN2 = 14;
// ===== MOTOR B: RIGHT =====
const int ENB = 25;
const int IN3 = 27;
const int IN4 = 26;
// ===== SERVO SG90 / PWM =====
const int SERVO_PIN = 22;
const int SERVO_MIN_US = 1000;
const int SERVO_MAX_US = 2000;
const int SERVO_AUTO_MIN = 60;
const int SERVO_AUTO_MAX = 120;
const int PWM_MOTOR_A = 0;
const int PWM_MOTOR_B = 1;
const int PWM_SERVO = 2;
bool pwmReady = false;
int servoManual = 90;
int servoAngle = 90;
int sweepDirection = 1;
unsigned long lastServoAt = 0;
bool sweeping = false;

// ===== FLAME SENSOR =====
const int FLAME_LEFT   = 18;
const int FLAME_CENTER = 19;
const int FLAME_RIGHT  = 5;
const int FLAME_DETECTED  = LOW;
// ===== PUMP =====
const int RELAY_PIN = 16;
const int RELAY_ON  = LOW;
const int RELAY_OFF = HIGH;
// ===== ULTRASONIC / MQ2 =====
const int TRIG_PIN = 17;
const int ECHO_PIN = 32;
const int MQ2_PIN  = 35;
const float MIN_DISTANCE_CM = 15.0;
const unsigned long COMMAND_TIMEOUT_MS = 1200;
// Front-range thresholds for basic autonomous patrol. The ultrasonic sensor
// measures objects, not the distance to a flame; no reverse travel is used.
const float AUTO_OBSTACLE_CM = 25.0;
const float AUTO_CLEAR_CM = 30.0;
const int AUTO_MAX_SPEED = 150;
const unsigned long AUTO_TURN_ACTIVE_MS = 350;
const unsigned long AUTO_TURN_CYCLE_MS = 650;
const unsigned long AUTO_FLAME_CLEAR_MS = 1500;
// ===== STATUS =====
enum Motion {
  STOP,
  FORWARD,
  BACKWARD,
  LEFT,
  RIGHT
};
// Explicit prototypes for Arduino sketch preprocessing of custom types.
void writeMotorOutputs(Motion motion);
void controlMotor(Motion target);
const char* motionName(Motion motion);
void planAuto(unsigned long now, Motion& target, bool& requestedPump);
bool modeAuto = false;
bool pumpManual = false;
bool pumpActive = false;
bool flameLeft = false;
bool flameCenter = false;
bool flameRight = false;
int motorSpeed = 150;
int mq2Raw = 0;
float distanceCm = -1;
Motion manualMotion = STOP;
Motion activeMotion = STOP;
Motion pendingMotion = STOP;
unsigned long lastCommandAt = 0;
unsigned long stoppedAt = 0;
unsigned long lastSensorAt = 0;
bool autoAvoiding = false;
bool autoRespondingToFlame = false;
unsigned long autoTurnStartedAt = 0;
unsigned long autoLastFlameAt = 0;

void resetAutoState() {
  autoAvoiding = false;
  autoRespondingToFlame = false;
  autoTurnStartedAt = millis();
  autoLastFlameAt = millis();
}

// ===== PWM MOTOR + SERVO =====
// Motor 20kHz and servo 50Hz use separate channels/timers.
void writePwm(int channel, uint32_t duty) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWriteChannel(channel, duty);
#else
  ledcWrite(channel, duty);
#endif
}

bool initializePwm() {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  bool a = ledcAttachChannel(ENA, 20000, 8, PWM_MOTOR_A);
  bool b = ledcAttachChannel(ENB, 20000, 8, PWM_MOTOR_B);
  bool c = ledcAttachChannel(SERVO_PIN, 50, 16, PWM_SERVO);
  return a && b && c;
#else
  bool a = ledcSetup(PWM_MOTOR_A, 20000, 8) > 0;
  bool b = ledcSetup(PWM_MOTOR_B, 20000, 8) > 0;
  bool c = ledcSetup(PWM_SERVO, 50, 16) > 0;
  ledcAttachPin(ENA, PWM_MOTOR_A);
  ledcAttachPin(ENB, PWM_MOTOR_B);
  ledcAttachPin(SERVO_PIN, PWM_SERVO);
  return a && b && c;
#endif
}

void setServo(int angle) {
  servoAngle = constrain(angle, 0, 180);
  uint32_t us = SERVO_MIN_US +
      (SERVO_MAX_US - SERVO_MIN_US) * servoAngle / 180;
  uint32_t duty = (us * 65536UL + 10000UL) / 20000UL;
  if (pwmReady) writePwm(PWM_SERVO, duty);
}

void controlServo(bool sweep, bool manualTimeout) {
  if (!modeAuto) {
    sweeping = false;
    setServo(manualTimeout ? 90 : servoManual);
    return;
  }
  if (!sweep) {
    sweeping = false;
    setServo(90);
    return;
  }
  if (!sweeping) {
    sweeping = true;
    sweepDirection = 1;
    lastServoAt = millis();
    setServo(90);
  }
  if (millis() - lastServoAt >= 100UL) {
    lastServoAt = millis();
    int angle = servoAngle + sweepDirection * 5;
    if (angle >= SERVO_AUTO_MAX) {
      angle = SERVO_AUTO_MAX;
      sweepDirection = -1;
    } else if (angle <= SERVO_AUTO_MIN) {
      angle = SERVO_AUTO_MIN;
      sweepDirection = 1;
    }
    setServo(angle);
  }
}

// ===== MOTOR =====
void stopMotor() {
  if (pwmReady) writePwm(PWM_MOTOR_A, 0);
  if (pwmReady) writePwm(PWM_MOTOR_B, 0);
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
}
void allOutputsOff() {
  stopMotor();
  digitalWrite(RELAY_PIN, RELAY_OFF);
  pumpActive = false;
}
void resetMotion() {
  allOutputsOff();
  activeMotion = STOP;
  pendingMotion = STOP;
  stoppedAt = millis();
}
void writeMotorOutputs(Motion motion) {
  switch (motion) {
    case FORWARD:
      // CONFIRMED: A1 + B1 = FORWARD
      digitalWrite(IN1, HIGH);
      digitalWrite(IN2, LOW);
      digitalWrite(IN3, HIGH);
      digitalWrite(IN4, LOW);
      break;

    case BACKWARD:
      // CONFIRMED: A2 + B2 = BACKWARD
      digitalWrite(IN1, LOW);
      digitalWrite(IN2, HIGH);
      digitalWrite(IN3, LOW);
      digitalWrite(IN4, HIGH);
      break;

    case LEFT:
      // A backward + B forward
      digitalWrite(IN1, LOW);
      digitalWrite(IN2, HIGH);
      digitalWrite(IN3, HIGH);
      digitalWrite(IN4, LOW);
      break;

    case RIGHT:
      // A forward + B backward
      digitalWrite(IN1, HIGH);
      digitalWrite(IN2, LOW);
      digitalWrite(IN3, LOW);
      digitalWrite(IN4, HIGH);
      break;

    case STOP:
      stopMotor();
      return;
  }

  const int outputSpeed = modeAuto && motorSpeed > AUTO_MAX_SPEED
      ? AUTO_MAX_SPEED : motorSpeed;
  writePwm(PWM_MOTOR_A, outputSpeed);
  writePwm(PWM_MOTOR_B, outputSpeed);
}

void controlMotor(Motion target) {
  if (motorSpeed == 0) target = STOP;
  if (target != pendingMotion) {
    stopMotor();
    activeMotion = STOP;
    pendingMotion = target;
    stoppedAt = millis();
  }
  if (target == STOP) {
    stopMotor();
    activeMotion = STOP;
    return;
  }
  if (millis() - stoppedAt < 100) return;
  writeMotorOutputs(target);
  activeMotion = target;
}
const char* motionName(Motion motion) {
  switch (motion) {
    case FORWARD: return "FORWARD";
    case BACKWARD: return "BACKWARD";
    case LEFT: return "LEFT";
    case RIGHT: return "RIGHT";
    default: return "STOP";
  }
}
// ===== DISTANCE SENSOR =====
float readDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  unsigned long duration =
      pulseIn(ECHO_PIN, HIGH, 25000UL);
  if (duration == 0) return -1;
  float cm = duration * 0.0343f / 2.0f;
  if (cm < 2 || cm > 400) return -1;
  return cm;
}
// ===== BINARY GATT PROTOCOL =====
const char* SERVICE_UUID = "7a1e0001-b5a3-f393-e0a9-e50e24dcca9e";
const char* COMMAND_UUID = "7a1e0002-b5a3-f393-e0a9-e50e24dcca9e";
const char* TELEMETRY_UUID = "7a1e0003-b5a3-f393-e0a9-e50e24dcca9e";
const size_t COMMAND_SIZE = 8;
const size_t TELEMETRY_SIZE = 20;

// Numeric values are shared with Flutter; do not reorder.
enum RobotStatus : uint8_t {
  IDLE = 0, MOVING = 1, FORWARD_BLOCKED = 2, SEARCHING = 3,
  SPRAYING = 4, OBSTACLE = 5, UNCLEAR = 6, SEARCH_REST = 7,
  LINK_TIMEOUT = 8, PWM_FAULT = 9,
  PATROLLING = 10, AVOIDING = 11, DISTANCE_UNKNOWN = 12, FIRE_CHECK = 13
};
RobotStatus statusCode = IDLE;

// Nonblocking patrol: the loop continues servicing STOP, sensor reads and
// the command watchdog during every turn, spray and flame-clear interval.
void planAuto(unsigned long now, Motion& target, bool& requestedPump) {
  target = STOP;
  requestedPump = false;
  const bool flame = flameLeft || flameCenter || flameRight;
  if (flame) {
    if (!autoRespondingToFlame) resetMotion();
    autoRespondingToFlame = true;
    autoLastFlameAt = now;
    autoAvoiding = false;
    if (flameCenter) {
      // Spray only while stationary. A missing echo does not prevent spraying.
      requestedPump = true;
      statusCode = SPRAYING;
    } else if (flameLeft && flameRight) {
      statusCode = UNCLEAR;
    } else if (distanceCm < 0) {
      statusCode = DISTANCE_UNKNOWN;
    } else if (distanceCm <= AUTO_OBSTACLE_CM) {
      statusCode = OBSTACLE;
    } else {
      target = flameLeft ? LEFT : RIGHT;
      statusCode = MOVING;
    }
    return;
  }
  if (autoRespondingToFlame) {
    if (now - autoLastFlameAt < AUTO_FLAME_CLEAR_MS) {
      statusCode = FIRE_CHECK;
      return;
    }
    autoRespondingToFlame = false;
  }
  if (distanceCm < 0) {
    autoAvoiding = false;
    statusCode = DISTANCE_UNKNOWN;
    return;
  }
  if (!autoAvoiding && distanceCm <= AUTO_OBSTACLE_CM) {
    autoAvoiding = true;
    autoTurnStartedAt = now;
  }
  if (autoAvoiding && distanceCm >= AUTO_CLEAR_CM) autoAvoiding = false;
  if (autoAvoiding) {
    // Brief in-place turns followed by a stationary sensor check. The motor
    // direction interlock includes its usual 100ms stop before each turn.
    const unsigned long phase = (now - autoTurnStartedAt) % AUTO_TURN_CYCLE_MS;
    target = phase < AUTO_TURN_ACTIVE_MS ? RIGHT : STOP;
    statusCode = AVOIDING;
    return;
  }
  target = FORWARD;
  statusCode = PATROLLING;
}
BLEServer* bleServer = nullptr;
BLECharacteristic* telemetry = nullptr;
uint8_t ackSequence = 0;
bool watchdogTripped = false;
bool hasCommand = false;

// Only this mailbox is shared with the BLE task. All hardware writes and
// mode changes happen on the Arduino loop task, never from BLE callbacks.
portMUX_TYPE mailboxMux = portMUX_INITIALIZER_UNLOCKED;
bool linkConnected = false;
bool linkResetRequested = false;
bool restartAdvertising = false;
bool requireStopCommand = true;
uint16_t controllerConnection = 0xffff;
uint32_t connectionEpoch = 0;
bool commandPending = false;
bool emergencyPending = false;
uint8_t pendingCommand[COMMAND_SIZE] = {};
uint32_t pendingAt = 0;
uint32_t pendingEpoch = 0;

bool stopHandshake(const uint8_t* data) {
  return data[2] == 2 ||
    (data[2] == 0 && data[3] == 0 && data[5] == 90 && data[6] == 0);
}

class RobotServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server, esp_ble_gatts_cb_param_t* param) override {
    bool reject = false;
    portENTER_CRITICAL(&mailboxMux);
    if (linkConnected) {
      reject = true;
    } else {
      linkConnected = true;
      controllerConnection = param->connect.conn_id;
      connectionEpoch++;
      linkResetRequested = true;
      requireStopCommand = true;
      commandPending = false;
      emergencyPending = false;
      restartAdvertising = false;
    }
    portEXIT_CRITICAL(&mailboxMux);
    if (reject) server->disconnect(param->connect.conn_id);
    // Advertising is not restarted while a controller is connected.
  }

  void onDisconnect(BLEServer*, esp_ble_gatts_cb_param_t* param) override {
    portENTER_CRITICAL(&mailboxMux);
    if (linkConnected && param->disconnect.conn_id == controllerConnection) {
      linkConnected = false;
      controllerConnection = 0xffff;
      connectionEpoch++;
      linkResetRequested = true;
      requireStopCommand = true;
      commandPending = false;
      emergencyPending = false;
      restartAdvertising = true;
    }
    portEXIT_CRITICAL(&mailboxMux);
  }
};

class RobotCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic,
               esp_ble_gatts_cb_param_t* param) override {
    // Read only conn_id from the callback union below: it is the common
    // prefix of WRITE and EXEC_WRITE. Payload validation uses the completed
    // characteristic value, so both callback variants are handled safely.
    const auto value = characteristic->getValue(); // String in 3.x / std::string in 2.x
    if (value.length() != COMMAND_SIZE) return;
    uint8_t data[COMMAND_SIZE];
    memcpy(data, value.c_str(), COMMAND_SIZE);
    if (data[0] != 1 || data[2] > 2 || data[3] > 4 || data[5] > 180 ||
        data[6] > 1 || data[7] != 0) return;
    // AUTO and emergency stop carry neutral manual outputs.
    if (data[2] != 0 && (data[3] != 0 || data[6] != 0 || data[5] != 90)) return;
    const bool isStop = stopHandshake(data);
    const uint32_t receivedAt = millis();
    portENTER_CRITICAL(&mailboxMux);
    if (linkConnected && param->write.conn_id == controllerConnection &&
        (!requireStopCommand || isStop) && !emergencyPending) {
      memcpy(pendingCommand, data, COMMAND_SIZE);
      pendingAt = receivedAt;
      pendingEpoch = connectionEpoch;
      commandPending = true;
      // A later packet cannot overwrite a pending emergency stop.
      if (data[2] == 2) emergencyPending = true;
    }
    portEXIT_CRITICAL(&mailboxMux);
  }
};

void stopEverything() {
  modeAuto = false;
  manualMotion = STOP;
  pumpManual = false;
  servoManual = 90;
  sweeping = false;
  resetAutoState();
  resetMotion();
  setServo(90);
}

void serviceCommands() {
  uint8_t data[COMMAND_SIZE] = {};
  bool connected, reset, pending, emergency;
  uint32_t receivedAt, epoch;
  portENTER_CRITICAL(&mailboxMux);
  connected = linkConnected;
  reset = linkResetRequested;
  linkResetRequested = false;
  epoch = connectionEpoch;
  pending = commandPending && pendingEpoch == epoch;
  emergency = emergencyPending;
  receivedAt = pendingAt;
  if (pending) memcpy(data, pendingCommand, COMMAND_SIZE);
  commandPending = false;
  emergencyPending = false;
  portEXIT_CRITICAL(&mailboxMux);

  if (reset || !connected) {
    stopEverything();
    hasCommand = false;
    watchdogTripped = !connected;
    statusCode = connected ? IDLE : LINK_TIMEOUT;
  }
  if (!connected || !pending) return;
  // Do not execute commands that sat in the mailbox beyond the timeout.
  if (millis() - receivedAt >= COMMAND_TIMEOUT_MS) return;
  if (emergency) data[2] = 2;
  if (data[2] == 2) {
    stopEverything();
  } else {
    const bool newAuto = data[2] == 1;
    if (newAuto != modeAuto) {
      stopEverything();
      modeAuto = newAuto;
    }
    motorSpeed = data[4];
    if (!modeAuto) {
      manualMotion = static_cast<Motion>(data[3]);
      servoManual = data[5];
      pumpManual = data[6] == 1;
      // Release direction and pump without waiting for the next control pass.
      if (manualMotion == STOP) {
        stopMotor();
        activeMotion = STOP;
        pendingMotion = STOP;
        stoppedAt = millis();
      }
      if (!pumpManual) {
        digitalWrite(RELAY_PIN, RELAY_OFF);
        pumpActive = false;
      }
    }
  }
  ackSequence = data[1];
  lastCommandAt = receivedAt;
  hasCommand = true;
  watchdogTripped = false;
  // Only the loop can complete the handshake; a command queued after this
  // connection was invalidated cannot rearm the new connection.
  portENTER_CRITICAL(&mailboxMux);
  if (linkConnected && connectionEpoch == epoch && stopHandshake(data)) {
    requireStopCommand = false;
  }
  portEXIT_CRITICAL(&mailboxMux);
}

bool commandLinkHealthy() {
  bool connected, reset;
  portENTER_CRITICAL(&mailboxMux);
  connected = linkConnected;
  reset = linkResetRequested;
  portEXIT_CRITICAL(&mailboxMux);
  return connected && !reset && hasCommand &&
    millis() - lastCommandAt < COMMAND_TIMEOUT_MS;
}

void tripWatchdog() {
  stopEverything();
  watchdogTripped = true;
  hasCommand = false;
  statusCode = LINK_TIMEOUT;
  portENTER_CRITICAL(&mailboxMux);
  requireStopCommand = true;
  commandPending = false;
  emergencyPending = false;
  portEXIT_CRITICAL(&mailboxMux);
}

void publishTelemetry() {
  uint8_t packet[TELEMETRY_SIZE] = {};
  packet[0] = 1;
  packet[1] = ackSequence;
  packet[2] = (modeAuto ? 1 : 0) | (pumpActive ? 2 : 0) |
    (flameLeft ? 4 : 0) | (flameCenter ? 8 : 0) | (flameRight ? 16 : 0) |
    (pwmReady ? 32 : 0) | (watchdogTripped ? 64 : 0);
  packet[3] = static_cast<uint8_t>(activeMotion);
  packet[4] = motorSpeed;
  packet[5] = servoAngle;
  const uint16_t distance = distanceCm < 0 ? 0xffff :
    static_cast<uint16_t>(distanceCm * 10.0f + 0.5f);
  packet[6] = distance & 0xff;
  packet[7] = distance >> 8;
  packet[8] = mq2Raw & 0xff;
  packet[9] = mq2Raw >> 8;
  const uint32_t uptime = millis() / 1000UL;
  for (uint8_t i = 0; i < 4; i++) packet[10 + i] = (uptime >> (8 * i)) & 0xff;
  packet[14] = static_cast<uint8_t>(statusCode);
  telemetry->setValue(packet, sizeof(packet));
  bool connected;
  portENTER_CRITICAL(&mailboxMux);
  connected = linkConnected;
  portEXIT_CRITICAL(&mailboxMux);
  if (connected) telemetry->notify();
}

void setup() {
  Serial.begin(115200);
  // Establish safe outputs before Bluetooth initialization.
  digitalWrite(RELAY_PIN, RELAY_OFF);
  pinMode(RELAY_PIN, OUTPUT);
  const int motorPins[] = {ENA, IN1, IN2, ENB, IN3, IN4};
  for (int pin : motorPins) {
    digitalWrite(pin, LOW);
    pinMode(pin, OUTPUT);
  }
  pinMode(FLAME_LEFT, INPUT_PULLUP);
  pinMode(FLAME_CENTER, INPUT_PULLUP);
  pinMode(FLAME_RIGHT, INPUT_PULLUP);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  digitalWrite(TRIG_PIN, LOW);
  pinMode(MQ2_PIN, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(MQ2_PIN, ADC_11db);
  pwmReady = initializePwm();
  stopEverything();
  if (!pwmReady) statusCode = PWM_FAULT;

  BLEDevice::init("FireGuard Robot");
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new RobotServerCallbacks());
  BLEService* service = bleServer->createService(SERVICE_UUID);
  BLECharacteristic* command = service->createCharacteristic(
    COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE);
  command->setCallbacks(new RobotCommandCallbacks());
  telemetry = service->createCharacteristic(TELEMETRY_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  telemetry->addDescriptor(new BLE2902());
  publishTelemetry();
  service->start();
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("FireGuard Robot • BLE ready • manual / stopped");
  Serial.println("Watchdog 1200ms in ALL modes. First command must be STOP.");
}

void loop() {
  serviceCommands();
  const unsigned long now = millis();
  if (now - lastSensorAt >= 100UL) {
    lastSensorAt = now;
    distanceCm = readDistance(); // Maximum blocking time: 25ms.
    mq2Raw = analogRead(MQ2_PIN);
  }
  flameLeft = digitalRead(FLAME_LEFT) == FLAME_DETECTED;
  flameCenter = digitalRead(FLAME_CENTER) == FLAME_DETECTED;
  flameRight = digitalRead(FLAME_RIGHT) == FLAME_DETECTED;

  if (!pwmReady) {
    stopEverything();
    statusCode = PWM_FAULT;
  } else if (!commandLinkHealthy()) {
    tripWatchdog();
  } else {
    Motion target = STOP;
    bool requestedPump = false;
    // Manual driving retains the original valid-distance cutoff. Auto patrol
    // requires a valid range and uses a larger stop-and-turn threshold.
    const bool obstacle = distanceCm >= 0 && distanceCm < MIN_DISTANCE_CM;
    if (!modeAuto) {
      target = manualMotion;
      requestedPump = pumpManual;
      if (target == FORWARD && obstacle) {
        target = STOP;
        statusCode = FORWARD_BLOCKED;
      } else {
        statusCode = target == STOP ? IDLE : MOVING;
      }
    } else {
      planAuto(now, target, requestedPump);
    }
    // Drop the pump before any new movement. Automatic spraying always
    // cancels pending motor movement before the relay can be energized.
    if (!requestedPump) {
      pumpActive = false;
      digitalWrite(RELAY_PIN, RELAY_OFF);
    }
    if (modeAuto && requestedPump) target = STOP;
    controlMotor(target);
    pumpActive = requestedPump && (!modeAuto || activeMotion == STOP);
    digitalWrite(RELAY_PIN, pumpActive ? RELAY_ON : RELAY_OFF);
    controlServo(modeAuto && requestedPump, false);
  }

  static unsigned long lastTelemetry = 0;
  if (now - lastTelemetry >= 250UL) {
    lastTelemetry = now;
    publishTelemetry();
  }
  bool advertise = false;
  portENTER_CRITICAL(&mailboxMux);
  if (restartAdvertising && !linkConnected) {
    restartAdvertising = false;
    advertise = true;
  }
  portEXIT_CRITICAL(&mailboxMux);
  if (advertise) BLEDevice::startAdvertising();
  delay(2);
}
