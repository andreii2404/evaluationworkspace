import 'package:flutter/material.dart';

const cantiereName = 'In Cantiere';

class CantiereWordmark extends StatelessWidget {
  const CantiereWordmark({
    super.key,
    this.iconOnly = false,
    this.dark = true,
    this.fontSize = 28,
  });

  final bool iconOnly;
  final bool dark;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: cantiereName,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CantiereSymbol(),
        if (!iconOnly) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'In ',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: dark
                          ? const Color(0xFFB9D9FF)
                          : const Color(0xFF0353A4),
                    ),
                  ),
                  const TextSpan(text: 'Cantiere'),
                ],
              ),
              style: TextStyle(
                fontFamily: 'Instrument Serif',
                color: dark ? Colors.white : const Color(0xFF001233),
                fontSize: fontSize,
                height: 1.1,
                letterSpacing: .15,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class CantiereSymbol extends StatelessWidget {
  const CantiereSymbol({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _BrandGlyph()),
  );
}

class _BrandGlyph extends CustomPainter {
  const _BrandGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    // Keep the emblem geometry in sync with web/favicon.svg.
    const bounds = Rect.fromLTWH(0, 0, 64, 64);
    final tile = RRect.fromRectAndRadius(bounds, const Radius.circular(16));
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0353A4), Color(0xFF001845)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      tile.deflate(.75),
      Paint()
        ..color = const Color(0x80B9D9FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(39, 19)
        ..arcToPoint(
          const Offset(39, 45),
          radius: const Radius.circular(15),
          largeArc: true,
          clockwise: false,
        ),
      stroke..color = Colors.white,
    );
    canvas.drawLine(
      const Offset(45, 27),
      const Offset(45, 37),
      stroke..color = const Color(0xFFB9D9FF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandGlyph oldDelegate) => false;
}
