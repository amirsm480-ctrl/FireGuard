import 'dart:typed_data';

enum RobotMode { manual, auto }

enum Motion { stop, forward, backward, left, right }

class RobotDevice {
  const RobotDevice({required this.id, required this.name, required this.rssi});
  final String id;
  final String name;
  final int rssi;
}

class ActivityEntry {
  const ActivityEntry({
    required this.at,
    required this.title,
    required this.detail,
    this.alert = false,
    this.demo = false,
  });
  final DateTime at;
  final String title;
  final String detail;
  final bool alert;
  final bool demo;
  Map<String, Object?> toMap() => {
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'detail': detail,
    'alert': alert ? 1 : 0,
  };
  factory ActivityEntry.fromMap(Map<String, Object?> map) => ActivityEntry(
    at: DateTime.fromMillisecondsSinceEpoch(map['at'] as int),
    title: map['title'] as String,
    detail: map['detail'] as String,
    alert: map['alert'] == 1,
  );
}

class Telemetry {
  const Telemetry({
    required this.mode,
    required this.motion,
    required this.speed,
    required this.servo,
    required this.distanceCm,
    required this.mq2,
    required this.flameLeft,
    required this.flameCenter,
    required this.flameRight,
    required this.pump,
    required this.pwmReady,
    required this.watchdogTripped,
    required this.uptimeSeconds,
    required this.acknowledgedSequence,
    required this.receivedAt,
    this.statusCode = 0,
  });
  final RobotMode mode;
  final Motion motion;
  final int speed;
  final int servo;
  final double? distanceCm;
  final int mq2;
  final bool flameLeft;
  final bool flameCenter;
  final bool flameRight;
  final bool pump;
  final bool pwmReady;
  final bool watchdogTripped;
  final int uptimeSeconds;
  final int acknowledgedSequence;
  final DateTime receivedAt;
  final int statusCode;
  bool get hasFlame => flameLeft || flameCenter || flameRight;
  bool get obstacle => distanceCm != null && distanceCm! < 15;
  String get statusLabel => const [
    'Robot stopped',
    'Robot moving',
    'Forward motion blocked',
    'Searching for flame',
    'Spraying water',
    'Obstacle nearby',
    'Flame direction unclear',
    'Search resting',
    'Connection timed out',
    'PWM unavailable',
    'Patrolling',
    'Avoiding obstacle',
    'Distance unavailable',
    'Checking for flame',
  ][statusCode];
  Map<String, Object?> toMap() => {
    'at': receivedAt.millisecondsSinceEpoch,
    'mode': mode.index,
    'motion': motion.index,
    'speed': speed,
    'servo': servo,
    'distance': distanceCm,
    'mq2': mq2,
    'flame_left': flameLeft ? 1 : 0,
    'flame_center': flameCenter ? 1 : 0,
    'flame_right': flameRight ? 1 : 0,
    'pump': pump ? 1 : 0,
    'pwm_ready': pwmReady ? 1 : 0,
    'watchdog': watchdogTripped ? 1 : 0,
    'uptime': uptimeSeconds,
    'ack': acknowledgedSequence,
    'status': statusCode,
  };
  factory Telemetry.fromMap(Map<String, Object?> map) => Telemetry(
    receivedAt: DateTime.fromMillisecondsSinceEpoch(map['at'] as int),
    mode: RobotMode.values[map['mode'] as int],
    motion: Motion.values[map['motion'] as int],
    speed: map['speed'] as int,
    servo: map['servo'] as int,
    distanceCm: (map['distance'] as num?)?.toDouble(),
    mq2: map['mq2'] as int,
    flameLeft: map['flame_left'] == 1,
    flameCenter: map['flame_center'] == 1,
    flameRight: map['flame_right'] == 1,
    pump: map['pump'] == 1,
    pwmReady: map['pwm_ready'] == 1,
    watchdogTripped: map['watchdog'] == 1,
    uptimeSeconds: map['uptime'] as int,
    acknowledgedSequence: map['ack'] as int,
    statusCode: map['status'] as int,
  );
}

/// Fixed binary frames fit the minimum BLE ATT payload (20 bytes).
abstract final class RobotProtocol {
  static const serviceUuid = '7a1e0001-b5a3-f393-e0a9-e50e24dcca9e';
  static const commandUuid = '7a1e0002-b5a3-f393-e0a9-e50e24dcca9e';
  static const telemetryUuid = '7a1e0003-b5a3-f393-e0a9-e50e24dcca9e';
  static List<int> command({
    required int sequence,
    required RobotMode mode,
    required Motion motion,
    required int speed,
    required int servo,
    required bool pump,
    bool emergency = false,
  }) {
    if (sequence < 0 ||
        sequence > 255 ||
        speed < 0 ||
        speed > 255 ||
        servo < 0 ||
        servo > 180) {
      throw const FormatException('Command out of range');
    }
    return [
      1,
      sequence,
      emergency ? 2 : mode.index,
      emergency ? 0 : motion.index,
      speed,
      emergency ? 90 : servo,
      !emergency && pump ? 1 : 0,
      0,
    ];
  }

  static Telemetry decode(List<int> bytes, {DateTime? receivedAt}) {
    if (bytes.length != 20 ||
        bytes[0] != 1 ||
        bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Incompatible BLE packet');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final flags = bytes[2];
    final distance = data.getUint16(6, Endian.little);
    final mq2 = data.getUint16(8, Endian.little);
    if (flags & 128 != 0 ||
        bytes[3] >= Motion.values.length ||
        bytes[5] > 180 ||
        mq2 > 4095 ||
        bytes[14] > 13 ||
        bytes.skip(15).any((b) => b != 0) ||
        (distance != 65535 && (distance < 20 || distance > 4000))) {
      throw const FormatException('Invalid BLE telemetry');
    }
    return Telemetry(
      mode: flags & 1 != 0 ? RobotMode.auto : RobotMode.manual,
      motion: Motion.values[bytes[3]],
      speed: bytes[4],
      servo: bytes[5],
      distanceCm: distance == 65535 ? null : distance / 10,
      mq2: mq2,
      flameLeft: flags & 4 != 0,
      flameCenter: flags & 8 != 0,
      flameRight: flags & 16 != 0,
      pump: flags & 2 != 0,
      pwmReady: flags & 32 != 0,
      watchdogTripped: flags & 64 != 0,
      uptimeSeconds: data.getUint32(10, Endian.little),
      acknowledgedSequence: bytes[1],
      receivedAt: receivedAt ?? DateTime.now(),
      statusCode: bytes[14],
    );
  }
}
