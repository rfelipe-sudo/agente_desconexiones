import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Tacómetro semicircular para Mi Equipo.
class MiEquipoGaugePainter extends CustomPainter {
  final double pct;
  final Color valueColor;

  MiEquipoGaugePainter({required this.pct, required this.valueColor});

  static const _labelStyle = TextStyle(
    color: Color(0xFF253A52),
    fontSize: 9,
    fontFamily: 'monospace',
  );

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.72;
    final radius = size.width * 0.42;
    const sw = 14.0;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1E2A35);
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    if (pct > 0.01) {
      final gradient = SweepGradient(
        center: Alignment.center,
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: const [
          Color(0xFFFF2255),
          Color(0xFFFF6D00),
          Color(0xFFFFCC00),
          Color(0xFF00F080),
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      );
      final gradientPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..shader = gradient.createShader(rect);
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle * pct.clamp(0.0, 1.0),
        false,
        gradientPaint,
      );
    }

    for (final mark in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final angle = math.pi + math.pi * mark;
      final inner = Offset(
        cx + (radius - sw - 3) * math.cos(angle),
        cy + (radius - sw - 3) * math.sin(angle),
      );
      final outer = Offset(
        cx + (radius + 4) * math.cos(angle),
        cy + (radius + 4) * math.sin(angle),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = const Color(0xFF253A52)
          ..strokeWidth = (mark == 0 || mark == 0.5 || mark == 1.0) ? 1.5 : 1.0,
      );
    }

    final needleAngle = math.pi + math.pi * pct.clamp(0.0, 1.0);
    final needleTip = Offset(
      cx + (radius - sw / 2 - 3) * math.cos(needleAngle),
      cy + (radius - sw / 2 - 3) * math.sin(needleAngle),
    );
    canvas.drawLine(
      Offset(cx, cy),
      needleTip,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(Offset(cx, cy), 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      12,
      Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final tp0 = TextPainter(
      text: const TextSpan(text: '0', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final tp100 = TextPainter(
      text: const TextSpan(text: '100%', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final tp50 = TextPainter(
      text: const TextSpan(text: '50%', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp0.paint(canvas, Offset(cx - radius - sw / 2 - 4, cy - tp0.height / 2));
    tp100.paint(
      canvas,
      Offset(cx + radius + sw / 2 - tp100.width + 2, cy - tp100.height / 2),
    );
    tp50.paint(canvas, Offset(cx - tp50.width / 2, cy - radius - sw / 2 - 16));
  }

  @override
  bool shouldRepaint(MiEquipoGaugePainter old) => old.pct != pct;
}
