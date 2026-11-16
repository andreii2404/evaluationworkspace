import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

class WorkshopGlass extends StatelessWidget {
  const WorkshopGlass({
    super.key,
    required this.child,
    this.featured = false,
    this.radius = 17,
  });

  final Widget child;
  final bool featured;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: featured && !highContrast
            ? const [
                BoxShadow(
                  color: Color(0x39495390),
                  blurRadius: 30,
                  spreadRadius: -4,
                  offset: Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: GlassSurface(
        radius: radius,
        blur: 14,
        tint: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .44, 1],
          colors: featured
              ? const [Color(0x8A202235), Color(0x8A10121F), Color(0xA8060810)]
              : const [Color(0x52282C3D), Color(0x69151A26), Color(0x8F090C15)],
        ),
        rimGradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x669FAAC4),
            Color(0x2C9DA9C5),
            Color(0x15727C99),
            Color(0x559CA7C1),
          ],
          stops: [0, .27, .68, 1],
        ),
        child: CustomPaint(
          foregroundPainter: highContrast
              ? null
              : _GlassReflections(radius, featured),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

class _GlassReflections extends CustomPainter {
  const _GlassReflections(this.radius, this.featured);

  final double radius;
  final bool featured;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = math.min(radius, size.shortestSide / 2);
    final span = size.width - 2 * inset;
    if (span <= 0) return;

    final bounds = Rect.fromLTWH(inset, 0, span, size.height);
    final edge = Paint()..strokeWidth = 1;
    final upper = featured ? const Color(0x9BCBD7F0) : const Color(0x57C5D2ED);
    final lower = featured ? const Color(0x718E9BDA) : const Color(0x3B9DACE4);
    edge.shader = LinearGradient(
      colors: [Colors.transparent, upper, Colors.transparent],
      stops: const [.02, .36, .89],
    ).createShader(bounds);
    canvas.drawLine(Offset(bounds.left, 1), Offset(bounds.right, 1), edge);

    edge.shader = LinearGradient(
      colors: [Colors.transparent, lower, Colors.transparent],
      stops: const [.13, .69, .98],
    ).createShader(bounds);
    canvas.drawLine(
      Offset(bounds.left, size.height - 1),
      Offset(bounds.right, size.height - 1),
      edge,
    );
  }

  @override
  bool shouldRepaint(_GlassReflections oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.featured != featured;
}

class WorkshopAction extends StatelessWidget {
  const WorkshopAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.minHeight = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double minHeight;

  @override
  Widget build(BuildContext context) => WorkshopGlass(
    radius: 99,
    featured: true,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFFF7F8FE),
        disabledForegroundColor: const Color(0xFFA3ACBF),
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        overlayColor: const Color(0xFFAABAF3),
        shape: const StadiumBorder(),
        minimumSize: Size(0, minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon case final icon?) ...[
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-.32, -.47),
                  colors: [Color(0xFF343B51), Color(0xFF141925)],
                ),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0x788993B3)),
                ),
              ),
              child: SizedBox.square(
                dimension: 27,
                child: Icon(icon, size: 16),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}
