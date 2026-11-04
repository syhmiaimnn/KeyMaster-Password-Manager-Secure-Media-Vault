import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A ring that fills up to [score] (0 to 100), with the number in the middle.
class ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  final double strokeWidth;
  final Widget? center;

  const ScoreRing({
    super.key,
    required this.score,
    this.size = 132,
    this.strokeWidth = 12,
    this.center,
  });

  /// Red when low, amber in the middle, green when good.
  static Color colorFor(Palette p, int score) {
    if (score >= 90) return p.accent;
    if (score >= 75) return p.success;
    if (score >= 55) return p.warning;
    return p.danger;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = colorFor(p, score);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: score.clamp(0, 100).toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              fraction: value / 100,
              track: p.border,
              start: p.primary,
              end: color,
              strokeWidth: strokeWidth,
            ),
            child: Center(
              child: center ??
                  Text(
                    '${value.round()}',
                    style: TextStyle(
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: p.text,
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color start;
  final Color end;
  final double strokeWidth;

  _RingPainter({
    required this.fraction,
    required this.track,
    required this.start,
    required this.end,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (fraction <= 0) return;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [start, end],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, arcPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.fraction != fraction ||
        old.track != track ||
        old.start != start ||
        old.end != end ||
        old.strokeWidth != strokeWidth;
  }
}
