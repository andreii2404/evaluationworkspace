import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A clipped, tinted surface with a bright upper rim and a blue lower edge.
/// Use blur where the surface actually overlaps imagery or other content.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 12,
    this.dark = true,
    this.tint,
  });

  final Widget child;
  final double radius;
  final double blur;
  final bool dark;
  final LinearGradient? tint;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    final highContrast = MediaQuery.highContrastOf(context);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        gradient:
            (!highContrast ? tint : null) ??
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: highContrast
                  ? (dark
                        ? const [Color(0xFF002855), Color(0xFF001233)]
                        : const [Colors.white, Color(0xFFF0F6FF)])
                  : (dark
                        ? const [Color(0xB3284D77), Color(0xDA001233)]
                        : const [Color(0xECFFFFFF), Color(0xBBD9EAFF)]),
            ),
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: corners,
          border: Border.all(
            color: highContrast
                ? (dark ? Colors.white : const Color(0xFF023E7D))
                : (dark ? const Color(0x80CCEBFF) : Colors.white),
          ),
        ),
        child: child,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: const [
          BoxShadow(
            color: Color(0x29001233),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: blur > 0 && !highContrast
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: panel,
              )
            : panel,
      ),
    );
  }
}

typedef LiquidNavItem = ({String label, IconData icon});

/// A Flutter interpretation of Nimbus UI's Waterline interaction.
class LiquidGlassNav extends StatefulWidget {
  const LiquidGlassNav({
    super.key,
    required this.items,
    required this.active,
    required this.onSelected,
    required this.compact,
  });

  final List<LiquidNavItem> items;
  final int active;
  final ValueChanged<int> onSelected;
  final bool compact;

  @override
  State<LiquidGlassNav> createState() => _LiquidGlassNavState();
}

class _LiquidGlassNavState extends State<LiquidGlassNav>
    with SingleTickerProviderStateMixin {
  static const _inset = 4.0;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: 1,
  );
  final _pointer = ValueNotifier<Offset?>(null);
  late final _repaint = Listenable.merge([_motion, _pointer]);
  late final _focusNodes = [
    for (final item in widget.items) FocusNode(debugLabel: item.label),
  ];
  late double _origin = widget.active.toDouble();
  int? _focused;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _motion.value = 1;
      _pointer.value = null;
    }
  }

  @override
  void didUpdateWidget(LiquidGlassNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    _origin = _leadingPosition(oldWidget.active);
    _play();
  }

  double _leadingPosition(int target) => lerpDouble(
    _origin,
    target.toDouble(),
    Curves.easeOutQuart.transform((_motion.value * 1.3).clamp(0.0, 1.0)),
  )!;

  void _play() {
    if (_reduceMotion) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  void _select(int index) {
    if (index == widget.active) {
      _origin = widget.active.toDouble();
      _play();
      setState(() {});
    }
    widget.onSelected(index);
  }

  KeyEventResult _arrowKey(FocusNode node, KeyEvent event) {
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (direction == 0 || event is! KeyDownEvent) return KeyEventResult.ignored;
    final current = _focused ?? widget.active;
    final next = (current + direction) % widget.items.length;
    _focusNodes[next].requestFocus();
    _select(next);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _motion.dispose();
    _pointer.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Landing page navigation',
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _arrowKey,
      child: MouseRegion(
        onHover: (event) {
          if (!_reduceMotion) _pointer.value = event.localPosition;
        },
        onExit: (_) => _pointer.value = null,
        child: GlassSurface(
          radius: 40,
          blur: 0,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _Waterline(
                animation: _motion,
                pointer: _pointer,
                repaint: _repaint,
                count: widget.items.length,
                origin: _origin,
                active: widget.active,
              ),
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: Row(
                  children: [
                    for (var index = 0; index < widget.items.length; index++)
                      Expanded(child: _button(index)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _button(int index) {
    final item = widget.items[index];
    final selected = index == widget.active;
    final icon = Icon(item.icon, size: widget.compact ? 20 : 16);
    final label = widget.compact
        ? icon
        : Wrap(
            spacing: 5,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              icon,
              Text(item.label, textAlign: TextAlign.center),
            ],
          );
    final button = TextButton(
      focusNode: _focusNodes[index],
      onFocusChange: (focused) {
        if (focused) _focused = index;
      },
      onPressed: () => _select(index),
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : const Color(0xFFD5E7FF),
        overlayColor: const Color(0xFFB9D9FF),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: selected && !_reduceMotion
          ? AnimatedBuilder(
              animation: _motion,
              child: label,
              builder: (context, child) {
                final t = _motion.value;
                final spring = math.sin(t * 3 * math.pi) * (1 - t);
                return Transform.translate(
                  offset: Offset(0, -3.8 * spring),
                  child: Transform.scale(scale: 1 + .13 * spring, child: child),
                );
              },
            )
          : label,
    );
    return Semantics(
      selected: selected,
      label: widget.compact ? item.label : null,
      child: widget.compact
          ? Tooltip(
              message: item.label,
              excludeFromSemantics: true,
              child: button,
            )
          : button,
    );
  }
}

class _Waterline extends CustomPainter {
  _Waterline({
    required this.animation,
    required this.pointer,
    required Listenable repaint,
    required this.count,
    required this.origin,
    required this.active,
  }) : super(repaint: repaint);

  final Animation<double> animation;
  final ValueListenable<Offset?> pointer;
  final int count;
  final double origin;
  final int active;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = _LiquidGlassNavState._inset;
    final slot = (size.width - 2 * inset) / count;
    final t = animation.value;
    double center(double item) => inset + slot * (item + .5);
    final lead = center(
      lerpDouble(
        origin,
        active.toDouble(),
        Curves.easeOutQuart.transform((t * 1.3).clamp(0.0, 1.0)),
      )!,
    );
    final tail = center(
      lerpDouble(
        origin,
        active.toDouble(),
        Curves.easeInOutCubic.transform(t),
      )!,
    );
    final y = size.height / 2;
    final gap = (lead - tail).abs();
    final height = size.height - 2 * inset;
    final split = gap > slot * .88;
    final trail = split ? lead : tail;
    final bounds = Rect.fromLTRB(
      math.min(lead, trail) - slot * .5 + 1,
      y - height * (.5 - .08 * math.sin(t * math.pi)),
      math.max(lead, trail) + slot * .5 - 1,
      y + height * (.5 - .08 * math.sin(t * math.pi)),
    );
    final drop = RRect.fromRectAndRadius(bounds, Radius.circular(height / 2));
    canvas.drawRRect(
      drop,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA3C7EDFF), Color(0x606DABFA), Color(0x704493E8)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      drop.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEEFFFFFF), Color(0x437DBBFF), Color(0xACB9D9FF)],
        ).createShader(bounds),
    );
    if (split) {
      for (var i = 1; i <= 3; i++) {
        final fraction = i / 4;
        final droplet = Offset(
          lerpDouble(tail, lead, fraction)!,
          y + math.sin(i * 2.6) * height * .18,
        );
        canvas.drawCircle(
          droplet,
          (3 + i * .6) * math.sin(math.pi * t),
          Paint()..color = const Color(0xA5C8ECFF),
        );
      }
    }
    if (t > .08 && t < 1) {
      final ripple = Rect.fromCenter(
        center: Offset(lead, y),
        width: slot * (.28 + t * 1.32),
        height: height * (.25 + t),
      );
      canvas.drawOval(
        ripple,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: (1 - t) * .48),
      );
    }
    if (pointer.value case final point?) {
      canvas.drawCircle(
        point,
        29,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withValues(alpha: .32), Colors.transparent],
          ).createShader(Rect.fromCircle(center: point, radius: 29)),
      );
    }
  }

  @override
  bool shouldRepaint(_Waterline oldDelegate) =>
      oldDelegate.origin != origin ||
      oldDelegate.active != active ||
      oldDelegate.count != count;
}
