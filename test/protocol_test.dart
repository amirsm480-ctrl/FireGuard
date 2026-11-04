import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireguard/domain.dart';

List<int> frame({int flags = 32, int distance = 65535, int ack = 7}) {
  final data = ByteData(20);
  data.setUint8(0, 1);
  data.setUint8(1, ack);
  data.setUint8(2, flags);
  data.setUint8(4, 150);
  data.setUint8(5, 90);
  data.setUint16(6, distance, Endian.little);
  data.setUint16(8, 1537, Endian.little);
  data.setUint32(10, 123456, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  test(
    'minimum-MTU telemetry decodes little endian fields and unknown distance',
    () {
      final value = RobotProtocol.decode(frame(flags: 32 | 1 | 2 | 8));
      expect(value.mode, RobotMode.auto);
      expect(value.flameCenter, true);
      expect(value.flameLeft, false);
      expect(value.pump, true);
      expect(value.distanceCm, isNull);
      expect(value.mq2, 1537);
      expect(value.uptimeSeconds, 123456);
      expect(value.acknowledgedSequence, 7);
      expect(RobotProtocol.decode(frame(distance: 145)).obstacle, true);
    },
  );
  test('malformed and out-of-range telemetry is rejected', () {
    for (final packet in [
      <int>[],
      frame()..[0] = 2,
      frame()..[5] = 181,
      frame()..[3] = 5,
      frame()..[19] = 1,
      frame()..[2] = 128,
      frame()..[14] = 14,
      frame(distance: 0),
    ]) {
      expect(() => RobotProtocol.decode(packet), throwsFormatException);
    }
  });
  test('patrol firmware status codes decode and survive history storage', () {
    const labels = {
      10: 'Patrolling',
      11: 'Avoiding obstacle',
      12: 'Distance unavailable',
      13: 'Checking for flame',
    };
    for (final entry in labels.entries) {
      final value = RobotProtocol.decode(frame(flags: 33)..[14] = entry.key);
      expect(value.mode, RobotMode.auto);
      expect(value.statusLabel, entry.value);
      expect(Telemetry.fromMap(value.toMap()).statusLabel, entry.value);
    }
  });
  test('emergency frame always stops motors and pump and centers nozzle', () {
    expect(
      RobotProtocol.command(
        sequence: 255,
        mode: RobotMode.auto,
        motion: Motion.forward,
        speed: 250,
        servo: 12,
        pump: true,
        emergency: true,
      ),
      [1, 255, 2, 0, 250, 90, 0, 0],
    );
  });
  test('commands reject unsafe values instead of truncating bytes', () {
    expect(
      () => RobotProtocol.command(
        sequence: 0,
        mode: RobotMode.manual,
        motion: Motion.stop,
        speed: 256,
        servo: 90,
        pump: false,
      ),
      throwsFormatException,
    );
  });
}
