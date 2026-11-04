import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fireguard/app_controller.dart';
import 'package:fireguard/domain.dart';
import 'package:fireguard/fireguard_app.dart';
import 'package:fireguard/services/history_repository.dart';
import 'package:fireguard/services/robot_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PreviewTransport implements RobotTransport {
  @override
  Stream<List<int>> get packets => const Stream.empty();
  @override
  Stream<bool> get connectionChanges => const Stream.empty();
  @override
  Stream<RobotDevice> scan() => const Stream.empty();
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> write(List<int> bytes) async {}
}

Future<AppController> mountApp(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  GlobalKey? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  final controller = AppController(
    transport: PreviewTransport(),
    repository: MemoryHistoryRepository(),
    clock: tester.binding.clock.now,
  );
  await controller.init();
  await controller.startDemo();
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: FireguardApp(controller: controller),
    ),
  );
  await tester.pump(const Duration(milliseconds: 20));
  return controller;
}

Future<void> navigate(WidgetTester tester, String name) async {
  final destination = find.byWidgetPredicate(
    (widget) => widget is NavigationDestination && widget.label == name,
  );
  if (destination.evaluate().isNotEmpty) {
    await tester.tap(destination);
  } else {
    await tester.tap(find.text(name).first);
  }
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> closeApp(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = await File('test/assets/Roboto-Regular.ttf').readAsBytes();
    final font = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await font.load();
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFont.load();
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0]) {
    testWidgets('all screens fit at width $width', (tester) async {
      final controller = await mountApp(tester, Size(width, 1024));
      expect(tester.takeException(), isNull);
      for (final page in ['Control', 'History', 'Devices', 'Overview']) {
        await navigate(tester, page);
        expect(tester.takeException(), isNull, reason: '$page at $width');
      }
      await closeApp(tester, controller);
    });
  }

  testWidgets('larger text fits on a phone', (tester) async {
    final controller = await mountApp(
      tester,
      const Size(390, 844),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    for (final page in ['Control', 'History', 'Devices']) {
      await navigate(tester, page);
      expect(tester.takeException(), isNull, reason: '$page with larger text');
    }
    await closeApp(tester, controller);
  });

  testWidgets('direction release and cancel stop; leaving control stops pump', (
    tester,
  ) async {
    final controller = await mountApp(tester, const Size(1024, 1100));
    await navigate(tester, 'Control');
    final forward = find.text('FORWARD');
    await tester.ensureVisible(forward);
    final gesture = await tester.startGesture(tester.getCenter(forward));
    await tester.pump();
    expect(controller.telemetry?.motion, Motion.forward);
    await gesture.up();
    await tester.pump();
    expect(controller.telemetry?.motion, Motion.stop);
    final cancelled = await tester.startGesture(tester.getCenter(forward));
    await tester.pump();
    expect(controller.telemetry?.motion, Motion.forward);
    await cancelled.cancel();
    await tester.pump();
    expect(controller.telemetry?.motion, Motion.stop);
    await controller.setPump(true);
    await controller.setServo(135);
    await navigate(tester, 'Overview');
    expect(controller.pumpRequested, false);
    expect(controller.servo, 90);
    expect(controller.selectedMode, RobotMode.manual);
    await closeApp(tester, controller);
  });

  if (const bool.fromEnvironment('GENERATE_PREVIEWS')) {
    for (final preview in {
      'ipad': const Size(1024, 1100),
      'phone': const Size(390, 844),
    }.entries) {
      testWidgets('generate ${preview.key} preview', (tester) async {
        final captureKey = GlobalKey();
        final controller = await mountApp(
          tester,
          preview.value,
          captureKey: captureKey,
        );
        expect(tester.takeException(), isNull);
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs').create(recursive: true);
          await File(
            'docs/preview-${preview.key}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await closeApp(tester, controller);
      });
    }
  }
}
