import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_controller.dart';
import '../domain.dart';
import 'components.dart';

class ControlPage extends StatelessWidget {
  const ControlPage({
    super.key,
    required this.controller,
    required this.onDevices,
  });
  final AppController controller;
  final VoidCallback onDevices;
  @override
  Widget build(BuildContext context) {
    final manual =
        controller.canControl && controller.selectedMode == RobotMode.manual;
    final drive = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Drive control',
            subtitle: 'Press and hold a direction. Release to stop.',
          ),
          const SizedBox(height: 22),
          SegmentedButton<RobotMode>(
            segments: const [
              ButtonSegment(
                value: RobotMode.manual,
                icon: Icon(Icons.gamepad_outlined, size: 17),
                label: Text('Manual'),
              ),
              ButtonSegment(
                value: RobotMode.auto,
                icon: Icon(Icons.auto_awesome_outlined, size: 17),
                label: Text('Auto'),
              ),
            ],
            selected: {controller.selectedMode},
            onSelectionChanged: controller.canControl
                ? (value) => unawaited(controller.setMode(value.first))
                : null,
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 22),
          if (controller.selectedMode == RobotMode.auto)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: orange.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Auto patrols, turns away from obstacles within 25 cm, and stops to face and spray a flame. After 1.5 seconds without flame, patrol resumes. Missing distance readings stop movement; Auto speed is capped at 150.',
                style: TextStyle(color: ink, fontSize: 12, height: 1.6),
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _DirectionPad(controller: controller, enabled: manual),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Motor speed',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${controller.speed}',
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
              const Text(
                ' / 255',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
          Slider(
            value: controller.speed.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            semanticFormatterCallback: (value) => '${value.round()} out of 255',
            onChanged: controller.canControl
                ? (value) => unawaited(controller.setSpeed(value.round()))
                : null,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOW',
                style: TextStyle(color: muted, fontSize: 9, letterSpacing: .7),
              ),
              Text(
                'HIGH',
                style: TextStyle(color: muted, fontSize: 9, letterSpacing: .7),
              ),
            ],
          ),
          const SizedBox(height: 23),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: canvasColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: muted, size: 16),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    controller.telemetry?.distanceCm == null
                        ? 'Distance is unavailable. Forward movement remains possible; monitor the path.'
                        : 'Forward movement is blocked below 15 cm. Reverse and turning remain available.',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final nozzle = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Suppression system',
            subtitle: 'Water pump & nozzle direction',
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: canvasColor,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.water_drop_outlined,
                    color: Color(0xFF4E8DCA),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Water pump',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        controller.telemetry?.pump == true
                            ? 'Relay active'
                            : 'Relay inactive',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: controller.pumpRequested,
                  onChanged: manual
                      ? (value) => unawaited(controller.setPump(value))
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          Center(
            child: SizedBox(
              height: 183,
              child: RobotIllustration(
                angle: controller.telemetry?.servo ?? 90,
                pump: controller.telemetry?.pump ?? false,
                active: controller.canControl,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nozzle angle',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${controller.servo}°',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: controller.servo.toDouble(),
            min: 0,
            max: 180,
            divisions: 180,
            semanticFormatterCallback: (value) => '${value.round()} degrees',
            onChanged: manual
                ? (value) => unawaited(controller.setServo(value.round()))
                : null,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0°', style: TextStyle(color: muted, fontSize: 10)),
              Text('90°', style: TextStyle(color: muted, fontSize: 10)),
              Text('180°', style: TextStyle(color: muted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: OutlinedButton.icon(
              onPressed: manual
                  ? () => unawaited(controller.setServo(90))
                  : null,
              icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
              label: const Text('Center nozzle'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Actual angle: ${controller.telemetry == null ? '—' : '${controller.telemetry!.servo}°'} · Auto sweep: 60–120°',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!controller.canControl) ...[
          Panel(
            padding: 17,
            child: Row(
              children: [
                const Icon(
                  Icons.bluetooth_disabled_rounded,
                  color: orange,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Connect your robot or open the demo to enable controls.',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onDevices, child: const Text('Devices')),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 730
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: drive),
                    const SizedBox(width: 20),
                    Expanded(child: nozzle),
                  ],
                )
              : Column(children: [drive, const SizedBox(height: 20), nozzle]),
        ),
        const SizedBox(height: 20),
        Panel(
          padding: 17,
          color: const Color(0xFFFFF0EC),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, color: orange, size: 19),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'A lost Bluetooth link or a 1.2-second command timeout stops the motor and pump in both modes. Use the stop button to return to Manual.',
                  style: TextStyle(
                    color: Color(0xFF9E5239),
                    fontSize: 11,
                    height: 1.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DirectionPad extends StatefulWidget {
  const _DirectionPad({required this.controller, required this.enabled});
  final AppController controller;
  final bool enabled;
  @override
  State<_DirectionPad> createState() => _DirectionPadState();
}

class _DirectionPadState extends State<_DirectionPad> {
  Motion? _held;
  int? _pointer;
  void _release() {
    if (_held == null) return;
    setState(() {
      _held = null;
      _pointer = null;
    });
    unawaited(widget.controller.stopMotion());
  }

  @override
  void didUpdateWidget(covariant _DirectionPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _held != null) {
      _held = null;
      _pointer = null;
      unawaited(widget.controller.stopMotion());
    }
  }

  Widget _key(Motion direction, IconData icon, String label) {
    final held = _held == direction;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '$label. Press and hold to move, release to stop.',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.enabled
            ? (event) {
                if (_pointer != null) return;
                setState(() {
                  _held = direction;
                  _pointer = event.pointer;
                });
                unawaited(HapticFeedback.selectionClick());
                unawaited(widget.controller.startMotion(direction));
              }
            : null,
        onPointerUp: (event) {
          if (event.pointer == _pointer) _release();
        },
        onPointerCancel: (event) {
          if (event.pointer == _pointer) _release();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: held ? orange : canvasColor,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: held ? orange : line),
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : .35,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: held ? Colors.white : ink, size: 26),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: held ? Colors.white : muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 248,
    child: Column(
      children: [
        _key(Motion.forward, Icons.keyboard_arrow_up_rounded, 'FORWARD'),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _key(Motion.left, Icons.keyboard_arrow_left_rounded, 'LEFT'),
            SizedBox(
              width: 76,
              height: 76,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: const Color(0xFFFFE9E2),
                  foregroundColor: orange,
                  disabledBackgroundColor: const Color(0xFFF1E8E4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                onPressed: widget.controller.canControl
                    ? () {
                        _release();
                        unawaited(widget.controller.emergencyStop());
                      }
                    : null,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.stop_rounded, size: 26),
                    Text(
                      'STOP',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _key(Motion.right, Icons.keyboard_arrow_right_rounded, 'RIGHT'),
          ],
        ),
        const SizedBox(height: 10),
        _key(Motion.backward, Icons.keyboard_arrow_down_rounded, 'REVERSE'),
      ],
    ),
  );
}
