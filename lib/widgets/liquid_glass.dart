import 'dart:math' as math;
import 'dart:ui'
    show
        FragmentProgram,
        FragmentShader,
        ImageFilter,
        PointerDeviceKind,
        lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
    this.rim,
  });

  final Widget child;
  final double radius;
  final double blur;
  final bool dark;
  final LinearGradient? tint;
  final Color? rim;

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
                : (rim ?? (dark ? const Color(0x80CCEBFF) : Colors.white)),
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
    with TickerProviderStateMixin {
  static const _inset = 4.0;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: 1,
  );
  late final _pointer = _WaterPointer(createTicker);
  late final _repaint = Listenable.merge([_motion, _pointer]);
  late final _focusNodes = [
    for (final item in widget.items) FocusNode(debugLabel: item.label),
  ];
  late double _origin = widget.active.toDouble();
  int? _focused;
  bool _reduceMotion = false;
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset(
        'assets/landing/waterline.frag',
      );
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (_) {
      // The painted drop is available while the shader loads or if it fails.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _motion.value = 1;
      _pointer.clear();
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
    _shader?.dispose();
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
          if (!_reduceMotion && event.kind == PointerDeviceKind.mouse) {
            _pointer.move(event.localPosition);
          }
        },
        onExit: (_) => _pointer.leave(),
        child: Listener(
          onPointerDown: (event) {
            if (!_reduceMotion) _pointer.press(event.localPosition);
          },
          child: GlassSurface(
            radius: 40,
            blur: 0,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _Waterline(
                  animation: _motion,
                  pointer: _pointer,
                  shader: _reduceMotion || MediaQuery.highContrastOf(context)
                      ? null
                      : _shader,
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
    ),
  );

  Widget _button(int index) {
    final item = widget.items[index];
    final selected = index == widget.active;
    Widget icon = Icon(item.icon, size: widget.compact ? 20 : 16);
    if (selected && !_reduceMotion) {
      icon = AnimatedBuilder(
        animation: _motion,
        child: icon,
        builder: (context, child) {
          final t = _motion.value;
          final spring = math.sin(t * 3 * math.pi) * (1 - t);
          return Transform.translate(
            offset: Offset(0, -1 - 3.8 * spring),
            child: Transform.scale(scale: 1.08 + .13 * spring, child: child),
          );
        },
      );
    }
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
      style:
          TextButton.styleFrom(
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
            animationDuration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            textStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  selected ||
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? const Color(0xFFF1F7FF)
                  : const Color(0xFFB9CBE2),
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: Color(0xFFB9D9FF), width: 1.5)
                  : BorderSide.none,
            ),
          ),
      child: label,
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

class _WaterPointer extends ChangeNotifier {
  _WaterPointer(Ticker Function(TickerCallback) createTicker) {
    _ticker = createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _inside = false;
  Offset position = Offset.zero;
  double strength = 0;
  double time = 0;
  Offset? tap;
  double tapAge = 0;

  void move(Offset point) {
    position = point;
    _inside = true;
    _wake();
  }

  void leave() => _inside = false;

  void press(Offset point) {
    tap = point;
    tapAge = 0;
    _wake();
  }

  void _wake() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = math.min(
      (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    _lastTick = elapsed;
    time += dt;
    final target = _inside ? 1.0 : 0.0;
    strength += (target - strength) * math.min(1, dt * 7);
    if (tap != null) {
      tapAge += dt;
      if (tapAge >= 2.4) tap = null;
    }
    if (!_inside && strength < .01 && tap == null) {
      strength = 0;
      _ticker.stop();
    }
    notifyListeners();
  }

  void clear() {
    _inside = false;
    strength = 0;
    tap = null;
    _ticker.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class _Waterline extends CustomPainter {
  _Waterline({
    required this.animation,
    required this.pointer,
    required this.shader,
    required Listenable repaint,
    required this.count,
    required this.origin,
    required this.active,
  }) : super(repaint: repaint);

  final Animation<double> animation;
  final _WaterPointer pointer;
  final FragmentShader? shader;
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
    if (shader case final effect?) {
      final radius = math.min(height, slot - 2) / 2;
      final straight = math.max(0.0, slot / 2 - radius - 1);
      final thin = math.min(gap / (2 * (straight + radius)), 1.0);
      final tap = pointer.tap ?? Offset.zero;
      // Uniforms follow the declaration order in waterline.frag.
      final uniforms = [
        size.width,
        size.height,
        lead,
        y,
        straight * (1 - .25 * thin),
        radius * (1 - .12 * thin),
        tail,
        y,
        straight * (1 - .8 * thin),
        radius * (1 - .5 * thin),
        1 - .16 * math.sin(t * math.pi),
        split ? math.sin(t * math.pi) : 0.0,
        pointer.time,
        pointer.position.dx,
        pointer.position.dy,
        pointer.strength,
        tap.dx,
        tap.dy,
        pointer.tapAge,
        pointer.tap == null ? 0.0 : .8,
        lead,
        y,
        t * .72,
        t > .08 && t < 1 ? .7 * (1 - t) : 0.0,
      ];
      for (var i = 0; i < uniforms.length; i++) {
        effect.setFloat(i, uniforms[i]);
      }
      canvas.drawRect(Offset.zero & size, Paint()..shader = effect);
      return;
    }
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
    if (pointer.strength > 0) {
      final point = pointer.position;
      canvas.drawCircle(
        point,
        29,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: .22 * pointer.strength),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: point, radius: 29)),
      );
    }
  }

  @override
  bool shouldRepaint(_Waterline oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.origin != origin ||
      oldDelegate.active != active ||
      oldDelegate.count != count;
}
