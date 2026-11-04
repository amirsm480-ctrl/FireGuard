import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain.dart';

const ink = Color(0xFF192333);
const muted = Color(0xFF788190);
const orange = Color(0xFFEF6B3C);
const teal = Color(0xFF268B7F);
const canvasColor = Color(0xFFF5F6F8);
const line = Color(0xFFEAECEF);

String clockText(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
String dateText(DateTime time) =>
    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}';

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = 22,
    this.color = Colors.white,
  });
  final Widget child;
  final double padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: color == Colors.white ? line : Colors.transparent,
      ),
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class StatusTag extends StatelessWidget {
  const StatusTag(
    this.text, {
    super.key,
    this.color = teal,
    this.icon,
    this.dark = false,
  });
  final String text;
  final Color color;
  final IconData? icon;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: dark ? .18 : .09),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, color: color, size: 13)
        else
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: canvasColor,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(icon, size: 28, color: muted),
        ),
        const SizedBox(height: 17),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class GasChart extends StatelessWidget {
  const GasChart({super.key, required this.samples, this.height = 150});
  final List<Telemetry> samples;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'MQ2 raw readings from ${samples.length} samples, range 0 to 4095',
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _GasPainter(samples)),
    ),
  );
}

class _GasPainter extends CustomPainter {
  _GasPainter(this.samples);
  final List<Telemetry> samples;
  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const top = 12.0;
    final bottom = size.height - 24;
    final width = size.width - left - 4;
    for (var i = 0; i <= 3; i++) {
      final y = top + (bottom - top) * i / 3;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()
          ..color = line
          ..strokeWidth = 1,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '${4095 - i * 1365}',
          style: const TextStyle(fontFamily: 'Roboto', fontSize: 9, color: muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(0, y - 5));
    }
    if (samples.isEmpty) return;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = left + width * i / math.max(samples.length - 1, 1);
      final y = bottom - (bottom - top) * samples[i].mq2.clamp(0, 4095) / 4095;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(left + (samples.length == 1 ? 0 : width), bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x30EF6B3C), Color(0x00EF6B3C)],
        ).createShader(Rect.fromLTWH(left, top, width, bottom - top)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = orange
        ..strokeWidth = 2.3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final lastX = left + (samples.length == 1 ? 0 : width);
    final lastY =
        bottom - (bottom - top) * samples.last.mq2.clamp(0, 4095) / 4095;
    canvas.drawCircle(
      Offset(lastX, lastY),
      5,
      Paint()..color = orange.withValues(alpha: .15),
    );
    canvas.drawCircle(Offset(lastX, lastY), 2.8, Paint()..color = orange);
    final label = TextPainter(
      text: const TextSpan(
        text: 'EARLIER',
        style: TextStyle(fontFamily: 'Roboto', fontSize: 8, letterSpacing: .7, color: muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(left, size.height - 10));
    final recent = TextPainter(
      text: const TextSpan(
        text: 'LATEST',
        style: TextStyle(fontFamily: 'Roboto', fontSize: 8, letterSpacing: .7, color: muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    recent.paint(canvas, Offset(size.width - recent.width, size.height - 10));
  }

  @override
  bool shouldRepaint(_GasPainter oldDelegate) => true;
}

class RobotIllustration extends StatelessWidget {
  const RobotIllustration({
    super.key,
    this.angle = 90,
    this.pump = false,
    this.active = false,
  });
  final int angle;
  final bool pump;
  final bool active;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Robot illustration, nozzle $angle degrees',
    child: AspectRatio(
      aspectRatio: 1.25,
      child: CustomPaint(
        painter: _RobotPainter(angle: angle, pump: pump, active: active),
      ),
    ),
  );
}

class _RobotPainter extends CustomPainter {
  _RobotPainter({
    required this.angle,
    required this.pump,
    required this.active,
  });
  final int angle;
  final bool pump;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = math.min(size.width / 300, size.height / 240);
    canvas.translate(size.width / 2, size.height / 2 + 8);
    canvas.scale(scale);
    final guide = Paint()
      ..color = const Color(0xFF4B5C70).withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (final r in [69.0, 99.0, 127.0]) {
      canvas.drawCircle(const Offset(0, -4), r, guide);
    }
    canvas.drawLine(const Offset(-145, -4), const Offset(145, -4), guide);
    canvas.drawLine(const Offset(0, -116), const Offset(0, 113), guide);
    for (final x in [-55.0, 55.0]) {
      final track = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, 15), width: 30, height: 133),
        const Radius.circular(11),
      );
      canvas.drawRRect(track, Paint()..color = const Color(0xFF0D1420));
      for (var y = -40.0; y < 77; y += 11) {
        canvas.drawLine(
          Offset(x - 10, y),
          Offset(x + 10, y),
          Paint()
            ..color = const Color(0xFF3B495C)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-43, -63, 86, 150),
      const Radius.circular(20),
    );
    canvas.drawShadow(Path()..addRRect(body), Colors.black, 15, false);
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF5F6F7), Color(0xFF9DADB9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-33, -52, 66, 128),
        const Radius.circular(13),
      ),
      Paint()..color = const Color(0xFFD7DEE4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-27, 21, 54, 47),
        const Radius.circular(7),
      ),
      Paint()..color = const Color(0xFF314457),
    );
    for (var y = 32.0; y <= 54; y += 7) {
      canvas.drawLine(
        Offset(-17, y),
        Offset(17, y),
        Paint()
          ..color = const Color(0xFF6A7A88)
          ..strokeWidth = 2,
      );
    }
    canvas.drawRect(
      const Rect.fromLTWH(-33, 7, 66, 5),
      Paint()..color = orange,
    );
    canvas.drawCircle(
      const Offset(0, -22),
      25,
      Paint()..color = const Color(0xFF9CAFBF),
    );
    canvas.drawCircle(
      const Offset(0, -22),
      18,
      Paint()..color = const Color(0xFF1C2D40),
    );
    canvas.save();
    canvas.translate(0, -22);
    canvas.rotate((angle - 90) * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, -59, 14, 59),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFE8774A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -62, 18, 11),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFFFBD87),
    );
    if (pump) {
      for (var i = -2; i <= 2; i++) {
        canvas.drawLine(
          Offset(i * 2.0, -70),
          Offset(i * 7.0, -103),
          Paint()
            ..color = const Color(0xFF77D3E7).withValues(alpha: .7)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    canvas.restore();
    for (final x in [-24.0, 0.0, 24.0]) {
      canvas.drawCircle(
        Offset(x, -50),
        4,
        Paint()
          ..color = active ? const Color(0xFF5DD6B7) : const Color(0xFF8A98A5),
      );
    }
    for (final x in [-31.0, 31.0]) {
      canvas.drawCircle(
        Offset(x, 68),
        2,
        Paint()..color = const Color(0xFF6D7C88),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RobotPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.pump != pump ||
      oldDelegate.active != active;
}

class ActivityList extends StatelessWidget {
  const ActivityList({super.key, required this.entries, this.limit = 5});
  final List<ActivityEntry> entries;
  final int limit;
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No activity yet',
        detail: 'Connect your robot to start recording activity.',
      );
    }
    final shown = entries.take(limit).toList();
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i != 0) const Divider(height: 25),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: (shown[i].alert ? orange : teal).withValues(
                    alpha: .08,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  shown[i].alert
                      ? Icons.local_fire_department_outlined
                      : Icons.check_rounded,
                  size: 17,
                  color: shown[i].alert ? orange : teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shown[i].title,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shown[i].detail,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                clockText(shown[i].at).substring(0, 5),
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
