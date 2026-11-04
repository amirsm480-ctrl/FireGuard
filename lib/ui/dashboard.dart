import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../domain.dart';
import 'components.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.controller,
    required this.onControl,
    required this.onDevices,
    required this.onHistory,
  });
  final AppController controller;
  final VoidCallback onControl;
  final VoidCallback onDevices;
  final VoidCallback onHistory;
  @override
  Widget build(BuildContext context) {
    final t = controller.telemetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(
          controller: controller,
          onControl: onControl,
          onDevices: onDevices,
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            if (width <= 0) return const SizedBox.shrink();

            final count = width >= 730 ? 4 : (width >= 320 ? 2 : 1);
            final tileWidth = (width - (count - 1) * 14) / count;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    icon: Icons.radar_rounded,
                    title: 'OBSTACLE DISTANCE',
                    value: t?.distanceCm?.toStringAsFixed(1) ?? '—',
                    unit: 'cm',
                    detail: t == null || t.distanceCm == null
                        ? 'Reading unavailable'
                        : t.obstacle
                        ? 'Close obstacle · <15 cm'
                        : 'Forward threshold: 15 cm',
                    warning: t?.obstacle ?? false,
                    color: teal,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    icon: Icons.air_rounded,
                    title: 'SMOKE / GAS',
                    value: t == null ? '—' : '${t.mq2}',
                    unit: 'ADC',
                    detail: 'MQ2 · raw reading / 4095',
                    color: orange,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    icon: Icons.water_drop_outlined,
                    title: 'WATER PUMP',
                    value: t == null
                        ? '—'
                        : t.pump
                        ? 'ON'
                        : 'OFF',
                    unit: '',
                    detail: t?.pump == true
                        ? 'Relay is active'
                        : 'Relay is inactive',
                    color: const Color(0xFF4E8DCA),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    icon: Icons.tune_rounded,
                    title: 'ROBOT MODE',
                    value: t == null
                        ? '—'
                        : t.mode == RobotMode.auto
                        ? 'AUTO'
                        : 'MANUAL',
                    unit: '',
                    detail: t?.statusLabel ?? 'Waiting for your robot',
                    color: const Color(0xFF8D7AC4),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, box) {
            final flame = _FlamePanel(controller: controller);
            final trend = _TrendPanel(controller: controller);
            if (box.maxWidth < 730) {
              return Column(
                children: [flame, const SizedBox(height: 20), trend],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: flame),
                const SizedBox(width: 20),
                Expanded(child: trend),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        Panel(
          child: Column(
            children: [
              SectionTitle(
                'Recent activity',
                subtitle: 'A clear view of every robot event',
                trailing: TextButton(
                  onPressed: onHistory,
                  child: const Text('View all'),
                ),
              ),
              const SizedBox(height: 20),
              ActivityList(entries: controller.activities, limit: 3),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              controller.isDemo ? Icons.science_outlined : Icons.cloud_outlined,
              size: 15,
              color: muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                controller.isDemo
                    ? 'Demo data stays in this preview. It is never sent to Firebase.'
                    : controller.databaseLabel,
                style: const TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.controller,
    required this.onControl,
    required this.onDevices,
  });
  final AppController controller;
  final VoidCallback onControl;
  final VoidCallback onDevices;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        colors: [Color(0xFF1E2C3F), Color(0xFF26394C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 500;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const StatusTag(
                  'ESP32 · FIREFIGHTER',
                  color: Color(0xFFAFBECC),
                  dark: true,
                ),
                StatusTag(
                  controller.isDemo
                      ? 'DEMO MODE'
                      : controller.isConnected
                      ? 'BLUETOOTH LE'
                      : 'OFFLINE',
                  color: controller.isDemo
                      ? const Color(0xFFFFBD87)
                      : controller.isConnected
                      ? const Color(0xFF6ED6BA)
                      : const Color(0xFFAFBECC),
                  dark: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              controller.isConnected || controller.isDemo
                  ? 'Your robot.\nAt a glance.'
                  : 'Ready when\nyou are.',
              style: TextStyle(
                fontSize: compact ? 28 : 34,
                height: 1.14,
                letterSpacing: -.9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              controller.isDemo
                  ? 'Explore a simulated mission.\nNo robot connected.'
                  : controller.isConnected
                  ? 'Monitor the scene. Stay in control.\nConnected directly over Bluetooth.'
                  : 'Connect your robot over Bluetooth\nto see live sensors and take control.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB4C1CE),
                height: 1.7,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: controller.canControl ? onControl : onDevices,
              icon: Icon(
                controller.canControl
                    ? Icons.gamepad_outlined
                    : Icons.bluetooth_searching_rounded,
                size: 17,
              ),
              label: Text(
                controller.canControl ? 'Open controls' : 'Connect robot',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 43),
              ),
            ),
            if (controller.telemetry != null) ...[
              const SizedBox(height: 16),
              Text(
                'LAST UPDATE  ${clockText(controller.telemetry!.receivedAt)}',
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1,
                  color: Color(0xFF9AACBD),
                ),
              ),
            ],
          ],
        );
        final robot = Column(
          children: [
            SizedBox(
              height: compact ? 190 : 232,
              child: RobotIllustration(
                angle: controller.telemetry?.servo ?? 90,
                pump: controller.telemetry?.pump ?? false,
                active: controller.isConnected || controller.isDemo,
              ),
            ),
            const Text(
              'FG—01  /  RESPONSE UNIT',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF97AABB),
                letterSpacing: 1.8,
              ),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text,
              const SizedBox(height: 12),
              Center(child: robot),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 5, child: text),
            const SizedBox(width: 10),
            Expanded(flex: 4, child: robot),
          ],
        );
      },
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.detail,
    required this.color,
    this.warning = false,
  });
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final String detail;
  final Color color;
  final bool warning;
  @override
  Widget build(BuildContext context) => Panel(
    padding: 17,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: muted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: .55,
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: warning ? orange : ink,
                  fontSize: value == 'MANUAL' ? 25 : 29,
                  letterSpacing: -.9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 5, bottom: 5),
                  child: Text(
                    unit,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child: Text(
            detail,
            maxLines: 2,
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: warning ? orange : muted,
            ),
          ),
        ),
      ],
    ),
  );
}

class _FlamePanel extends StatelessWidget {
  const _FlamePanel({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final t = controller.telemetry;
    return Panel(
      child: Column(
        children: [
          SectionTitle(
            'Flame detection',
            subtitle: 'Three points. One clear picture.',
            trailing: Icon(
              Icons.local_fire_department_outlined,
              color: muted,
              size: 20,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i != 0) const SizedBox(width: 9),
                Expanded(
                  child: _FlameCell(
                    label: const ['Left', 'Center', 'Right'][i],
                    active: t == null
                        ? null
                        : [t.flameLeft, t.flameCenter, t.flameRight][i],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (t?.hasFlame == true ? orange : teal).withValues(
                alpha: .06,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(
                  t?.hasFlame == true
                      ? Icons.warning_amber_rounded
                      : Icons.shield_outlined,
                  size: 16,
                  color: t?.hasFlame == true ? orange : teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t == null
                        ? 'Waiting for sensor readings'
                        : controller.isStale
                        ? 'Last reading · connection is stale'
                        : t.hasFlame
                        ? 'Flame detected by the robot'
                        : 'No flame detected by the sensors',
                    style: TextStyle(
                      fontSize: 11,
                      color: t?.hasFlame == true ? orange : teal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlameCell extends StatelessWidget {
  const _FlameCell({required this.label, required this.active});
  final String label;
  final bool? active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 5),
    decoration: BoxDecoration(
      color: active == true ? const Color(0xFFFFF0E9) : canvasColor,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(
        color: active == true
            ? orange.withValues(alpha: .3)
            : Colors.transparent,
      ),
    ),
    child: Column(
      children: [
        Icon(
          Icons.local_fire_department_outlined,
          color: active == true ? orange : const Color(0xFFA4ADB7),
          size: 27,
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: ink,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          active == null
              ? 'NO DATA'
              : active!
              ? 'DETECTED'
              : 'CLEAR',
          style: TextStyle(
            color: active == null
                ? muted
                : active!
                ? orange
                : teal,
            fontSize: 8,
            letterSpacing: .5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: [
        SectionTitle(
          'Air sensor trend',
          subtitle: 'MQ2 · last ${controller.samples.length} samples',
          trailing: const StatusTag('RAW ADC', color: orange),
        ),
        const SizedBox(height: 14),
        Stack(
          alignment: Alignment.center,
          children: [
            GasChart(samples: controller.samples, height: 151),
            if (controller.samples.isEmpty)
              const Text(
                'Your readings will appear here',
                style: TextStyle(color: muted, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Uncalibrated sensor values · not ppm or AQI',
          style: TextStyle(fontSize: 10, color: muted),
        ),
      ],
    ),
  );
}
