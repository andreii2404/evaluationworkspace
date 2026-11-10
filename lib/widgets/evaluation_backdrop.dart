import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../app_theme.dart';

class EvaluationBackdrop extends StatelessWidget {
  const EvaluationBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) {
      return const ColoredBox(color: workshopNight);
    }
    return const RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10264A), workshopNight, Color(0xFF0A2345)],
                stops: [0, .52, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.72, -.18),
                radius: .85,
                colors: [
                  Color(0xA31E4F86),
                  Color(0x33113258),
                  Colors.transparent,
                ],
                stops: [0, .54, 1],
              ),
            ),
          ),
          CustomPaint(painter: _EvaluationDrawing()),
        ],
      ),
    );
  }
}

class _EvaluationDrawing extends CustomPainter {
  const _EvaluationDrawing();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    _draftingLines(canvas, size, bounds);
    final grid = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..shader = const RadialGradient(
        center: Alignment(.65, .62),
        radius: .85,
        colors: [Color(0x5091ABC9), Color(0x0A91ABC9), Colors.transparent],
        stops: [0, .65, 1],
      ).createShader(bounds);
    canvas.drawPoints(PointMode.points, [
      for (double x = 14; x < size.width; x += 24)
        for (double y = 14; y < size.height; y += 24) Offset(x, y),
    ], grid);

    if (size.width < 780 || size.height < 500) return;
    const drawingWidth = 476.0;
    final scale = math.min(1.16, size.width * .42 / drawingWidth);
    final rightInset = math.max(54.0, (size.width - 1400) / 2 + 32);
    canvas.save();
    canvas.translate(
      size.width - drawingWidth * scale - rightInset,
      size.height - 140 * scale - 30,
    );
    canvas.scale(scale);

    final trace = Paint()
      ..color = const Color(0x5D88B7E5)
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(120, 81)
        ..lineTo(150, 81)
        ..lineTo(150, 58)
        ..lineTo(178, 58)
        ..moveTo(298, 58)
        ..lineTo(328, 58)
        ..lineTo(328, 81)
        ..lineTo(356, 81),
      trace,
    );
    final dot = Paint()..color = const Color(0x7CB9D9FF);
    for (final anchor in const [
      Offset(150, 81),
      Offset(150, 58),
      Offset(328, 58),
      Offset(328, 81),
    ]) {
      canvas.drawCircle(anchor, 2, dot);
    }
    _plate(canvas, const Offset(0, 44), '01   PROJECT', _document);
    _plate(canvas, const Offset(178, 21), '02   REVIEW', _checklist);
    _plate(canvas, const Offset(356, 44), '03   FEEDBACK', _feedback);
    canvas.restore();
  }

  void _draftingLines(Canvas canvas, Size size, Rect bounds) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.transparent, Color(0x4784BAF4), Colors.transparent],
        stops: [0, .52, 1],
      ).createShader(bounds);
    for (final shift in [0.0, 24.0, 48.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width * .16 + shift, 0)
          ..lineTo(size.width * .48 + shift, size.height * .42)
          ..lineTo(size.width * .78 + shift, size.height * .42)
          ..lineTo(size.width + shift, size.height * .72),
        paint,
      );
    }
  }

  void _plate(
    Canvas canvas,
    Offset origin,
    String label,
    void Function(Canvas, Paint) drawIcon,
  ) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final box = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 120, 74),
      const Radius.circular(11),
    );
    canvas.drawRRect(box, Paint()..color = const Color(0xA8202E3E));
    final stroke = Paint()
      ..color = const Color(0x4A9CBFDE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(box, stroke);
    canvas.save();
    canvas.translate(13, 12);
    drawIcon(
      canvas,
      stroke
        ..color = const Color(0x83B9D9FF)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.25,
    );
    canvas.restore();
    final caption = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: 'Manrope',
          color: Color(0xA0B9D9FF),
          fontWeight: FontWeight.w700,
          fontSize: 8,
          letterSpacing: 1.35,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    caption.paint(canvas, const Offset(13, 53));
    caption.dispose();
    canvas.restore();
  }

  void _document(Canvas canvas, Paint stroke) {
    canvas.drawPath(
      Path()
        ..moveTo(2, 1)
        ..lineTo(19, 1)
        ..lineTo(25, 7)
        ..lineTo(25, 30)
        ..lineTo(2, 30)
        ..close()
        ..moveTo(19, 1)
        ..lineTo(19, 7)
        ..lineTo(25, 7)
        ..moveTo(7, 14)
        ..lineTo(20, 14)
        ..moveTo(7, 20)
        ..lineTo(20, 20)
        ..moveTo(7, 25)
        ..lineTo(15, 25),
      stroke,
    );
  }

  void _checklist(Canvas canvas, Paint stroke) {
    for (final y in [6.0, 16.0, 26.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(2, y)
          ..lineTo(5, y + 3)
          ..lineTo(10, y - 3)
          ..moveTo(15, y)
          ..lineTo(28, y),
        stroke,
      );
    }
  }

  void _feedback(Canvas canvas, Paint stroke) {
    canvas.drawPath(
      Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 2, 28, 21),
            const Radius.circular(4),
          ),
        )
        ..moveTo(8, 23)
        ..lineTo(8, 29)
        ..lineTo(15, 23)
        ..moveTo(8, 10)
        ..lineTo(24, 10)
        ..moveTo(8, 16)
        ..lineTo(19, 16),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_EvaluationDrawing oldDelegate) => false;
}
