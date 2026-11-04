import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireguard/app_controller.dart';
import 'package:fireguard/domain.dart';
import 'package:fireguard/services/history_repository.dart';
import 'package:fireguard/services/robot_transport.dart';
import 'protocol_test.dart' as fixture;

class FakeTransport implements RobotTransport {
  final packetController = StreamController<List<int>>.broadcast();
  final linkController = StreamController<bool>.broadcast();
  final List<List<int>> writes = [];
  bool connected = false;
  bool respond = true;
  Completer<void>? nextWriteGate;
  @override
  Stream<List<int>> get packets => packetController.stream;
  @override
  Stream<bool> get connectionChanges => linkController.stream;
  @override
  Stream<RobotDevice> scan() =>
      Stream.value(const RobotDevice(id: 'test', name: 'FireGuard', rssi: -50));
  @override
  Future<void> connect(String deviceId) async {
    connected = true;
  }

  @override
  Future<void> write(List<int> bytes) async {
    writes.add(List.of(bytes));
    final gate = nextWriteGate;
    nextWriteGate = null;
    if (gate != null) await gate.future;
    if (respond) packetController.add(fixture.frame(ack: bytes[1]));
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> dispose() async {
    await packetController.close();
    await linkController.close();
  }
}

const robot = RobotDevice(id: 'test', name: 'FireGuard', rssi: -50);
void main() {
  testWidgets('controls stay disabled until STOP is acknowledged', (
    tester,
  ) async {
    final transport = FakeTransport()..respond = false;
    final controller = AppController(
      transport: transport,
      repository: MemoryHistoryRepository(),
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.connect(robot);
    expect(controller.canControl, false);
    await controller.startMotion(Motion.forward);
    expect(transport.writes.single[2], 2);
    expect(transport.writes.single[3], 0);
    transport.packetController.add(
      fixture.frame(ack: transport.writes.single[1]),
    );
    await tester.pump();
    expect(controller.canControl, true);
    controller.dispose();
    await tester.pump();
  });
  testWidgets('release stops direction and background stops all outputs', (
    tester,
  ) async {
    final transport = FakeTransport();
    final controller = AppController(
      transport: transport,
      repository: MemoryHistoryRepository(),
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.connect(robot);
    await tester.pump();
    expect(controller.canControl, true);
    await controller.startMotion(Motion.forward);
    expect(transport.writes.last[3], 1);
    await controller.stopMotion();
    expect(transport.writes.last[3], 0);
    await controller.setPump(true);
    controller.onAppBackground();
    await tester.pump();
    expect(transport.writes.last[2], 2);
    expect(transport.writes.last[6], 0);
    expect(controller.canControl, false);
    expect(transport.connected, false);
    controller.onAppForeground();
    expect(controller.canControl, false);
    controller.dispose();
    await tester.pump();
  });
  testWidgets(
    'stale telemetry disconnects; late packets cannot resume motion',
    (tester) async {
      final transport = FakeTransport();
      final controller = AppController(
        transport: transport,
        repository: MemoryHistoryRepository(),
        clock: tester.binding.clock.now,
      );
      await controller.init();
      await controller.connect(robot);
      await tester.pump();
      await controller.startMotion(Motion.forward);
      await tester.pump();
      transport.respond = false;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(controller.canControl, false);
      expect(transport.connected, false);
      transport.packetController.add(
        fixture.frame(ack: transport.writes.last[1]),
      );
      await tester.pump();
      expect(controller.canControl, false);
      controller.dispose();
      await tester.pump();
    },
  );
  testWidgets('STOP supersedes an older in-flight movement command', (
    tester,
  ) async {
    final transport = FakeTransport();
    final controller = AppController(
      transport: transport,
      repository: MemoryHistoryRepository(),
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.connect(robot);
    await tester.pump();
    final gate = Completer<void>();
    transport.nextWriteGate = gate;
    final moving = controller.startMotion(Motion.forward);
    final stopping = controller.emergencyStop();
    gate.complete();
    await moving;
    await stopping;
    expect(transport.writes.last[2], 2);
    expect(transport.writes.last[3], 0);
    expect(transport.writes.last[6], 0);
    controller.dispose();
    await tester.pump();
  });
  testWidgets('fresh telemetry without command acknowledgement disconnects', (
    tester,
  ) async {
    final transport = FakeTransport();
    final controller = AppController(
      transport: transport,
      repository: MemoryHistoryRepository(),
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.connect(robot);
    await tester.pump();
    final oldAck = transport.writes.last[1];
    transport.respond = false;
    for (var i = 0; i < 6; i++) {
      transport.packetController.add(fixture.frame(ack: oldAck));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(controller.canControl, false);
    expect(transport.connected, false);
    controller.dispose();
    await tester.pump();
  });
  testWidgets('demo never writes cloud history or real BLE commands', (
    tester,
  ) async {
    final transport = FakeTransport();
    final repository = MemoryHistoryRepository();
    final controller = AppController(
      transport: transport,
      repository: repository,
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.startDemo();
    await controller.setMode(RobotMode.auto);
    await tester.pump(const Duration(seconds: 6));
    expect(controller.isDemo, true);
    expect(controller.canControl, true);
    expect(controller.isConnected, false);
    expect(transport.writes, isEmpty);
    expect(await repository.sampleCount(), 0);
    expect(await repository.recentActivities(), isEmpty);
    expect(await controller.exportCsv(), contains('demo,'));
    await controller.stopDemo();
    expect(controller.samples, isEmpty);
    controller.dispose();
    await tester.pump();
  });
  testWidgets('auto demo patrols, avoids, sprays while stopped, and resumes', (
    tester,
  ) async {
    final transport = FakeTransport();
    final controller = AppController(
      transport: transport,
      repository: MemoryHistoryRepository(),
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.startDemo();
    await controller.setMode(RobotMode.auto);
    expect(controller.telemetry!.statusCode, 10);
    expect(controller.telemetry!.motion, Motion.forward);
    final seen = <int>{10};
    var turnedRight = false;
    var turnedLeft = false;
    for (var tick = 1; tick <= 72; tick++) {
      await tester.pump(const Duration(milliseconds: 250));
      final sample = controller.telemetry!;
      seen.add(sample.statusCode);
      turnedRight |= sample.motion == Motion.right;
      turnedLeft |= sample.motion == Motion.left;
      if (sample.pump) {
        expect(sample.flameCenter, true);
        expect(sample.motion, Motion.stop);
      }
      if (sample.statusCode == 13 || sample.distanceCm == null) {
        expect(sample.motion, Motion.stop);
        expect(sample.pump, false);
      }
      if (tick >= 52 && tick < 58) {
        expect(sample.statusCode, 13);
      }
    }
    expect(seen, containsAll([10, 11, 1, 4, 13, 12]));
    expect(turnedRight, true);
    expect(turnedLeft, true);
    expect(controller.telemetry!.motion, Motion.forward);
    expect(controller.telemetry!.pump, false);
    expect(transport.writes, isEmpty);
    controller.dispose();
    await tester.pump();
  });
  testWidgets('zero motor speed stops every auto demo motion stage', (
    tester,
  ) async {
    final controller = AppController(
      transport: FakeTransport(),
      repository: MemoryHistoryRepository(),
      clock: tester.binding.clock.now,
    );
    await controller.init();
    await controller.startDemo();
    await controller.setSpeed(0);
    await controller.setMode(RobotMode.auto);
    for (var tick = 0; tick < 72; tick++) {
      expect(controller.telemetry!.motion, Motion.stop);
      await tester.pump(const Duration(milliseconds: 250));
    }
    controller.dispose();
    await tester.pump();
  });
}
