import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../widgets/cantiere_wordmark.dart';
import '../widgets/liquid_glass.dart';

const _smartBlue = Color(0xFF0466C8);
const _sapphire = Color(0xFF0353A4);
const _regal = Color(0xFF023E7D);
const _prussian = Color(0xFF002855);
const _navy = Color(0xFF001845);
const _ink = Color(0xFF001233);
const _indigo = Color(0xFF33415C);
const _grey = Color(0xFF7D8597);
const _silver = Color(0xFF979DAC);
const _paper = Color(0xFFF8FAFD);
const _mist = Color(0xFFEDF3FB);
const _rule = Color(0xFFD6DFED);
const _lightBlue = Color(0xFFB9D9FF);

TextStyle _type(
  double size, {
  Color color = _ink,
  int weight = 500,
  double height = 1.45,
  double spacing = 0,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontVariations: [FontVariation('wght', weight.toDouble())],
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: spacing,
);

TextStyle _display(double size, {Color color = _ink}) =>
    _type(size, color: color, weight: 800, height: 1.06, spacing: -size * .049);

Widget _eyebrow(String label, {Color color = _sapphire}) =>
    Text(label, style: _type(9, color: color, weight: 800, spacing: 1.65));

Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _top = GlobalKey();
  final _workflow = GlobalKey();
  final _audience = GlobalKey();
  final _trust = GlobalKey();
  final _header = GlobalKey();
  final _scroll = ScrollController();
  final _active = ValueNotifier(0);
  final _waterDrift = ValueNotifier(0.0);
  final _readingProgress = ValueNotifier(0.0);
  int _navigation = 0;
  bool _jumping = false;

  late final _sections = [_top, _workflow, _audience, _trust];

  static const List<LiquidNavItem> _links = [
    (label: 'Home', icon: Icons.home_outlined),
    (label: 'How it works', icon: Icons.layers_outlined),
    (label: 'Who can join', icon: Icons.group_outlined),
    (label: 'Safety', icon: Icons.shield_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  double get _headerClearance =>
      (_header.currentContext?.size?.height ?? 60) + 24;

  double? _offset(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    return RenderAbstractViewport.of(
      object,
    ).getOffsetToReveal(object, 0).offset;
  }

  void _onScroll() {
    final position = _scroll.position;
    final offset = position.pixels;
    if (position.hasContentDimensions) _updateReadingProgress(position);
    _waterDrift.value = (offset * .11).clamp(0.0, 62.0);
    if (_jumping) return;

    final readingLine = offset + _headerClearance + 18;
    var current = 0;
    for (var i = 1; i < _sections.length; i++) {
      final top = _offset(_sections[i]);
      if (top != null && top <= readingLine) current = i;
    }
    _active.value = current;
  }

  void _updateReadingProgress(ScrollMetrics metrics) {
    final extent = metrics.maxScrollExtent;
    _readingProgress.value = extent > 0
        ? (metrics.pixels / extent).clamp(0.0, 1.0)
        : 0.0;
  }

  Future<void> _go(int index) async {
    final top = _offset(_sections[index]);
    if (!_scroll.hasClients || top == null) return;
    final destination = (top - _headerClearance).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _active.value = index;
    final request = ++_navigation;
    _jumping = true;
    final duration = _motion(context, 700);
    try {
      if (duration == Duration.zero) {
        _scroll.jumpTo(destination);
      } else {
        await _scroll.animateTo(
          destination,
          duration: duration,
          curve: Curves.easeInOutCubic,
        );
      }
    } finally {
      if (mounted && request == _navigation) {
        _jumping = false;
        if ((_scroll.offset - destination).abs() > 2) _onScroll();
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _active.dispose();
    _waterDrift.dispose();
    _readingProgress.dispose();
    super.dispose();
  }

  void _logIn() => Navigator.pushNamed(context, '/login');

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    body: Stack(
      children: [
        SelectionArea(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) {
                _updateReadingProgress(notification.metrics);
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WaterStage(
                    key: _top,
                    drift: _waterDrift,
                    child: _PageWidth(
                      child: LayoutBuilder(
                        builder: (context, box) => Padding(
                          padding: EdgeInsets.only(
                            top: box.maxWidth >= 920 ? 153 : 172,
                            bottom: box.maxWidth >= 920 ? 68 : 38,
                          ),
                          child: _Hero(onLogin: _logIn, onSteps: () => _go(1)),
                        ),
                      ),
                    ),
                  ),
                  const _ProjectTypes(),
                  const _Reveal(child: _BrandStory()),
                  _GlassField(
                    key: _workflow,
                    child: const _PageWidth(
                      child: _Section(child: _Workflow()),
                    ),
                  ),
                  _GlassField(
                    key: _audience,
                    inverted: true,
                    child: const _PageWidth(
                      child: _Section(child: _Audience()),
                    ),
                  ),
                  _WaterStage(
                    key: _trust,
                    child: const _PageWidth(child: _Section(child: _Trust())),
                  ),
                  const _GlassField(
                    child: _PageWidth(child: _Section(child: _Questions())),
                  ),
                  ColoredBox(
                    color: _ink,
                    child: _PageWidth(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const CantiereWordmark(),
                            _TextAction(
                              'Back to top',
                              dark: true,
                              onPressed: () => _go(0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: _PageWidth(
            child: LayoutBuilder(
              builder: (context, box) {
                final scaler = MediaQuery.textScalerOf(context);
                final wide = box.maxWidth >= 960 && scaler.scale(12) <= 15;
                final nav = ValueListenableBuilder<int>(
                  valueListenable: _active,
                  builder: (context, active, _) => LiquidGlassNav(
                    items: _links,
                    active: active,
                    onSelected: _go,
                    compact: !wide,
                  ),
                );
                final account = _Action('Log in', onPressed: _logIn);
                final controls = Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  child: wide
                      ? Row(
                          children: [
                            const CantiereWordmark(),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 655,
                                  ),
                                  child: nav,
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            account,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: CantiereWordmark(
                                    fontSize: 23,
                                    iconOnly:
                                        box.maxWidth < 94 + scaler.scale(154),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: box.maxWidth * .56,
                                  ),
                                  child: account,
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            nav,
                          ],
                        ),
                );
                return GlassSurface(
                  key: _header,
                  radius: wide ? 36 : 27,
                  blur: 15,
                  child: Stack(
                    children: [
                      controls,
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 0,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _readingProgress,
                            builder: (context, progress, _) =>
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: const SizedBox(
                                    height: 2,
                                    child: ColoredBox(color: _lightBlue),
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _WaterStage extends StatelessWidget {
  const _WaterStage({super.key, this.drift, required this.child});

  final ValueListenable<double>? drift;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/landing/waterline.webp',
      fit: BoxFit.cover,
      alignment: const Alignment(.48, .25),
      excludeFromSemantics: true,
      errorBuilder: (context, error, stack) => const ColoredBox(color: _regal),
    );
    return ColoredBox(
      color: _ink,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            top: -68,
            child: drift != null && !MediaQuery.disableAnimationsOf(context)
                ? ValueListenableBuilder<double>(
                    valueListenable: drift!,
                    child: image,
                    builder: (context, offset, photo) => Transform.translate(
                      offset: Offset(0, offset),
                      child: photo,
                    ),
                  )
                : image,
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xF4001233),
                    Color(0xCD001845),
                    Color(0x30002855),
                  ],
                  stops: [0, .44, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x7A001233),
                    Colors.transparent,
                    Color(0xD8001233),
                  ],
                  stops: [0, .52, 1],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({super.key, this.inverted = false, required this.child});

  final bool inverted;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: inverted
            ? const [Color(0xFFCFDFF5), _paper, Color(0xFFDCEBFF)]
            : const [_paper, Color(0xFFDBE9FC), Color(0xFFBFD7F4)],
      ),
    ),
    child: child,
  );
}

class _PageWidth extends StatelessWidget {
  const _PageWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1344),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: box.maxWidth < 600 ? 22 : 44,
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Padding(
      padding: EdgeInsets.symmetric(vertical: box.maxWidth < 600 ? 55 : 88),
      child: child,
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(
    this.label, {
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.dark = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool secondary;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final foreground = secondary && !dark ? _navy : Colors.white;
    final style = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(foreground),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        final hover = states.contains(WidgetState.hovered);
        final pressed = states.contains(WidgetState.pressed);
        if (secondary) {
          return dark
              ? (hover ? const Color(0x80659CDF) : const Color(0x403B77BF))
              : (hover ? _mist : Colors.transparent);
        }
        if (pressed) return _regal;
        return hover ? _sapphire : _smartBlue;
      }),
      elevation: WidgetStateProperty.resolveWith(
        (states) => !secondary && states.contains(WidgetState.hovered) ? 3 : 0,
      ),
      shadowColor: const WidgetStatePropertyAll(Color(0x6682BFFF)),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return (dark || !secondary ? Colors.white : _smartBlue).withValues(
            alpha: .18,
          );
        }
        return null;
      }),
      textStyle: WidgetStatePropertyAll(_type(11, weight: 800)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 17, vertical: 11),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      shape: WidgetStatePropertyAll(const StadiumBorder()),
      animationDuration: _motion(context, 180),
      side: secondary
          ? WidgetStatePropertyAll(BorderSide(color: dark ? _grey : _silver))
          : null,
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        if (icon case final glyph?) ...[
          const SizedBox(width: 9),
          Icon(glyph, size: 17),
        ],
      ],
    );
    return secondary
        ? OutlinedButton(onPressed: onPressed, style: style, child: content)
        : FilledButton(onPressed: onPressed, style: style, child: content);
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction(this.label, {required this.onPressed, this.dark = false});

  final String label;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: dark ? Colors.white : _regal,
      textStyle: _type(11, weight: 800),
      minimumSize: const Size(0, 44),
      shape: const StadiumBorder(),
    ),
    child: Text(label),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onLogin, required this.onSteps});

  final VoidCallback onLogin;
  final VoidCallback onSteps;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 920;
      final headingSize = wide
          ? (box.maxWidth * .067).clamp(55.0, 88.0)
          : (box.maxWidth * .138).clamp(38.0, 76.0);
      final intro = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('PROJECT REVIEWS', color: _lightBlue),
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text.rich(
              const TextSpan(
                text: 'Put your work\n',
                children: [
                  TextSpan(
                    text: 'to the test.',
                    style: TextStyle(color: _lightBlue),
                  ),
                ],
              ),
              style: _display(headingSize - 2, color: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Text(
              '$cantiereName helps students and creators share their projects, ask people to try them, and see what to improve.',
              style: _type(
                wide ? 15 : 14,
                color: const Color(0xFFD8E8FC),
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Action(
                'Log in',
                onPressed: onLogin,
                icon: Icons.arrow_outward_rounded,
              ),
              _Action(
                'See how it works',
                onPressed: onSteps,
                secondary: true,
                dark: true,
                icon: Icons.south_rounded,
              ),
            ],
          ),
        ],
      );
      return wide
          ? Row(
              children: [
                Expanded(flex: 10, child: intro),
                const SizedBox(width: 32),
                const Expanded(flex: 12, child: _HeroPhoto()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 37), const _HeroPhoto()],
            );
    },
  );
}

class _HeroPhoto extends StatefulWidget {
  const _HeroPhoto();

  @override
  State<_HeroPhoto> createState() => _HeroPhotoState();
}

class _HeroPhotoState extends State<_HeroPhoto> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final wide = width >= 450;
      final height = (width * .75).clamp(305.0, 510.0);
      final reduce = MediaQuery.disableAnimationsOf(context);
      return MouseRegion(
        onEnter: (_) {
          if (!reduce) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: reduce ? 1 : 0,
              end: _hovered && !reduce ? 1.24 : 1,
            ),
            duration: _motion(context, _hovered ? 540 : 1150),
            curve: Curves.easeOutCubic,
            builder: (context, spread, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: wide ? 23 : 19,
                  left: wide ? 58 : 25,
                  right: wide ? 31 : 17,
                  bottom: 69,
                  child: Transform.translate(
                    offset: Offset((wide ? 18 : 5) * spread, -14 * spread),
                    child: Transform.rotate(
                      angle: (wide ? .118 : .087) * spread,
                      alignment: Alignment.bottomCenter,
                      child: const GlassSurface(
                        blur: 8,
                        radius: 25,
                        tint: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0x91D5F1FF), Color(0x505298D9)],
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 24 + 22 * (1 - spread),
                  left: wide ? 36 : 2,
                  right: wide ? 58 : 13,
                  bottom: wide ? 53 : 61,
                  child: Transform.rotate(
                    angle: -.026 * spread,
                    child: _PhotoSheet(compact: !wide),
                  ),
                ),
                Positioned(
                  bottom: (wide ? 17 : 8) + 24 * (1 - spread),
                  left: (wide ? 11 : 10) * spread,
                  width: (width - 22).clamp(0.0, 335.0),
                  child: Transform.rotate(
                    angle: -.049 * spread,
                    child: GlassSurface(
                      radius: 18,
                      blur: 14,
                      tint: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xA532669F), Color(0xD0001233)],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const _IconTile(
                              Icons.rate_review_outlined,
                              dark: true,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _eyebrow('SAMPLE REVIEW', color: _lightBlue),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Show a confirmation after someone books.',
                                    style: _type(
                                      12,
                                      color: Colors.white,
                                      weight: 700,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 24,
    blur: 0,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(17)),
            child: _Photo(
              asset: 'team-study',
              description: 'Students discussing work around a study table',
              alignment: Alignment(0, -.23),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(17)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [.38, 1],
                colors: [Colors.transparent, Color(0xD9001233)],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: compact ? 10 : null,
            bottom: compact ? null : 15,
            child: Align(
              alignment: Alignment.centerRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xD0001233),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  child: _eyebrow(
                    'CAMPUS CLINIC / PROTOTYPE',
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Photo extends StatelessWidget {
  const _Photo({
    required this.asset,
    required this.description,
    this.alignment = Alignment.center,
  });

  final String asset;
  final String description;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/landing/$asset.webp',
    semanticLabel: description,
    fit: BoxFit.cover,
    alignment: alignment,
    errorBuilder: (context, error, stack) => const ColoredBox(color: _prussian),
  );
}

class _ProjectTypes extends StatelessWidget {
  const _ProjectTypes();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: _navy,
      border: Border.symmetric(
        horizontal: BorderSide(color: Color(0x668DB6DF)),
      ),
    ),
    child: _PageWidth(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 21),
        child: Wrap(
          spacing: 30,
          runSpacing: 13,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _eyebrow('WHAT YOU CAN REVIEW', color: _lightBlue),
            for (final (icon, label) in const [
              (Icons.school_outlined, 'Capstones & research'),
              (Icons.view_in_ar_outlined, 'Apps & prototypes'),
              (Icons.sports_esports_outlined, 'Games & playtests'),
              (Icons.draw_outlined, 'Design & creative work'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: _lightBlue),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: _type(11, color: Colors.white, weight: 800),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

class _BrandStory extends StatelessWidget {
  const _BrandStory();

  @override
  Widget build(BuildContext context) => _PageWidth(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CantiereSymbol(size: 56),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Why $cantiereName?', style: _display(22)),
                ),
                const SizedBox(height: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 590),
                  child: Text(
                    '$cantiereName is Italian for “in the works.” It’s the stage when your project is ready for others to try and there’s still time to act on what they find.',
                    style: _type(13, color: _indigo, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.label,
    required this.title,
    required this.body,
    this.dark = false,
  });

  final String label;
  final String title;
  final String body;
  final bool dark;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(label, color: dark ? _lightBlue : _sapphire),
        const SizedBox(height: 13),
        Semantics(
          header: true,
          child: Text(
            title,
            style: _display(
              box.maxWidth < 530 ? 38 : 52,
              color: dark ? Colors.white : _ink,
            ),
          ),
        ),
        const SizedBox(height: 15),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 535),
          child: Text(
            body,
            style: _type(14, color: dark ? _lightBlue : _indigo),
          ),
        ),
      ],
    ),
  );
}

class _Workflow extends StatefulWidget {
  const _Workflow();

  @override
  State<_Workflow> createState() => _WorkflowState();
}

class _WorkflowState extends State<_Workflow> {
  final _sample = GlobalKey();
  int _selected = 0;

  void _select(int step, {required bool revealSample}) {
    if (step == _selected) return;
    setState(() => _selected = step);
    if (!revealSample) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sample.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: _motion(context, 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  static const _steps = [
    (
      title: 'Add your project',
      detail:
          'Add a link to your work, choose a review checklist, and describe what you want reviewed.',
    ),
    (
      title: 'Invite a reviewer',
      detail:
          'Check a reviewer’s skills and portfolio, then send a request they can accept or decline.',
    ),
    (
      title: 'Read your feedback',
      detail:
          'Compare scores item by item. Use the written notes to spot where people got stuck and decide what to change.',
    ),
  ];

  @override
  Widget build(BuildContext context) => _Reveal(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          label: 'HOW IT WORKS',
          title: 'Get feedback in three steps.',
          body:
              'Each reviewer scores the same checklist, so you can compare feedback. Pick a step to follow a sample project.',
        ),
        const SizedBox(height: 27),
        LayoutBuilder(
          builder: (context, box) {
            final stacked = box.maxWidth < 810;
            final sample = _ReviewSample(key: _sample, step: _selected);
            final buttons = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  _StepButton(
                    number: i + 1,
                    title: _steps[i].title,
                    detail: _steps[i].detail,
                    selected: i == _selected,
                    onPressed: () => _select(i, revealSample: stacked),
                  ),
                  if (stacked && i == _selected) ...[
                    const SizedBox(height: 8),
                    sample,
                  ],
                  const SizedBox(height: 9),
                ],
              ],
            );
            if (stacked) return buttons;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: buttons),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: sample),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.number,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onPressed,
  });

  final int number;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: OutlinedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          selected ? const Color(0xEFF4F9FF) : const Color(0xA9FFFFFF),
        ),
        foregroundColor: const WidgetStatePropertyAll(_sapphire),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(15)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 66)),
        alignment: Alignment.centerLeft,
        animationDuration: _motion(context, 160),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color:
                selected ||
                    states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? _smartBlue
                : _rule,
          ),
        ),
      ),
      child: Row(
        children: [
          Text('0$number', style: _type(10, color: _sapphire, weight: 800)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _type(15, weight: 800)),
                if (selected) ...[
                  const SizedBox(height: 6),
                  Text(detail, style: _type(12, color: _indigo)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 9),
          Icon(
            selected
                ? Icons.arrow_forward_rounded
                : Icons.chevron_right_rounded,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class _ReviewSample extends StatelessWidget {
  const _ReviewSample({super.key, required this.step});

  final int step;

  Widget _preview() => switch (step) {
    0 => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SampleLine(
          icon: Icons.link_rounded,
          title: 'Project link added',
          detail: 'Campus Clinic app prototype · Private',
        ),
        SizedBox(height: 10),
        _SampleLine(
          icon: Icons.checklist_rounded,
          title: 'Review checklist',
          detail: 'Ease of use and clear instructions',
        ),
      ],
    ),
    1 => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SamplePerson(icon: Icons.person_outline, label: 'You'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: _sapphire,
                size: 20,
              ),
            ),
            Expanded(
              child: _SamplePerson(
                icon: Icons.rate_review_outlined,
                label: 'Reviewer',
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        _SampleLine(
          icon: Icons.task_alt_rounded,
          title: 'Invite accepted',
          detail: 'Review task: book an appointment on your phone.',
        ),
      ],
    ),
    _ => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SampleScore(label: 'Ease of use', score: 4),
        SizedBox(height: 10),
        _SampleScore(label: 'Clear instructions', score: 3),
        SizedBox(height: 14),
        _SampleLine(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Reviewer’s note',
          detail: 'Show a confirmation after someone books.',
        ),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 455;
      return GlassSurface(
        radius: 24,
        blur: 0,
        child: ColoredBox(
          color: const Color(0xA6002855),
          child: CustomPaint(
            painter: const _Grid(),
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _eyebrow('EXAMPLE PROJECT', color: _lightBlue),
                      Text(
                        'Step ${step + 1} of 3',
                        style: _type(10, color: Colors.white, weight: 800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: _motion(context, 220),
                    layoutBuilder: (current, _) =>
                        current ?? const SizedBox.shrink(),
                    child: GlassSurface(
                      key: ValueKey(step),
                      radius: 15,
                      dark: false,
                      blur: 0,
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 13 : 19),
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Campus Clinic',
                                style: _type(21, weight: 800, spacing: -.6),
                              ),
                              const SizedBox(height: 12),
                              _preview(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SampleLine extends StatelessWidget {
  const _SampleLine({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xBFFFFFFF),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _sapphire),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _type(12, weight: 800)),
                const SizedBox(height: 2),
                Text(detail, style: _type(11, color: _indigo)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SamplePerson extends StatelessWidget {
  const _SamplePerson({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xBFFFFFFF),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
      child: Column(
        children: [
          Icon(icon, size: 21, color: _sapphire),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: _type(11, weight: 800),
          ),
        ],
      ),
    ),
  );
}

class _SampleScore extends StatelessWidget {
  const _SampleScore({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        runSpacing: 3,
        children: [
          Text(label, style: _type(11, weight: 700)),
          Text('$score / 5', style: _type(11, weight: 800, color: _regal)),
        ],
      ),
      const SizedBox(height: 5),
      ExcludeSemantics(
        child: LinearProgressIndicator(
          value: score / 5,
          minHeight: 7,
          backgroundColor: const Color(0xFFCBDDF1),
          color: _smartBlue,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    ],
  );
}

class _Grid extends CustomPainter {
  const _Grid();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x20B9D9FF)
      ..strokeWidth = 1;
    const gap = 27.0;
    for (var x = gap; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = gap; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Grid oldDelegate) => false;
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon, {this.dark = false});

  final IconData icon;
  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: dark ? _prussian : _mist,
      borderRadius: BorderRadius.circular(8),
    ),
    child: SizedBox.square(
      dimension: 40,
      child: Icon(icon, size: 21, color: dark ? _lightBlue : _sapphire),
    ),
  );
}

class _Audience extends StatelessWidget {
  const _Audience();

  @override
  Widget build(BuildContext context) => _Reveal(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          label: 'WHO CAN JOIN',
          title: 'Share or review a project.',
          body:
              'Students, creators, and reviewers can take part from anywhere.',
        ),
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, box) {
            const creator = _AudienceCard(
              number: '01',
              label: 'FOR STUDENTS & CREATORS',
              title: 'Share your work.',
              detail:
                  'Share a capstone, prototype, or game. Ask reviewers to try it and tell you where they got stuck.',
              photo: 'creator-notes',
              description: 'A student making notes beside a laptop',
            );
            const reviewer = _AudienceCard(
              number: '02',
              label: 'FOR REVIEWERS',
              title: 'Review someone’s work.',
              detail:
                  'Try the project as a peer, expert, or first-time user. Follow the checklist and explain what worked and what could improve.',
              photo: 'review-discussion',
              description: 'A group discussing a project around a laptop',
            );
            if (box.maxWidth < 700) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [creator, SizedBox(height: 17), reviewer],
              );
            }
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: creator),
                SizedBox(width: 20),
                Expanded(child: reviewer),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _AudienceCard extends StatefulWidget {
  const _AudienceCard({
    required this.number,
    required this.label,
    required this.title,
    required this.detail,
    required this.photo,
    required this.description,
  });

  final String number;
  final String label;
  final String title;
  final String detail;
  final String photo;
  final String description;

  @override
  State<_AudienceCard> createState() => _AudienceCardState();
}

class _AudienceCardState extends State<_AudienceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GlassSurface(
      dark: false,
      blur: 0,
      radius: 23,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2.15,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: AnimatedScale(
                  scale: _hovered && !MediaQuery.disableAnimationsOf(context)
                      ? 1.045
                      : 1,
                  duration: _motion(context, 320),
                  curve: Curves.easeOutCubic,
                  child: _Photo(
                    asset: widget.photo,
                    description: widget.description,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('${widget.number}   /   ${widget.label}'),
                  const SizedBox(height: 9),
                  Semantics(
                    header: true,
                    child: Text(widget.title, style: _display(30)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.detail,
                    style: _type(13, color: _indigo, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Trust extends StatelessWidget {
  const _Trust();

  static const _features = [
    (
      Icons.lock_outline_rounded,
      'Control who sees your project',
      'Keep it private, invite someone directly, or share it with the signed-in community. Your linked files have their own access settings.',
    ),
    (
      Icons.badge_outlined,
      'Check reviewer profiles',
      'Reviewers list their own skills and portfolio links. Check their profile to see if they fit your project.',
    ),
    (
      Icons.fact_check_outlined,
      'Disclose conflicts and report concerns',
      'Evaluators declare conflicts of interest when submitting a review. Signed-in members can report community projects for moderation.',
    ),
  ];

  @override
  Widget build(BuildContext context) => _Reveal(
    child: LayoutBuilder(
      builder: (context, box) {
        const introduction = _SectionTitle(
          label: 'SAFETY',
          title: 'Privacy and safety.',
          body:
              'Choose who can see your project and learn who is reviewing it.',
          dark: true,
        );
        final features = GlassSurface(
          blur: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (icon, title, detail) in _features) ...[
                  const Divider(height: 1, color: _indigo),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconTile(icon, dark: true),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: _type(
                                  15,
                                  color: Colors.white,
                                  weight: 800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                detail,
                                style: _type(
                                  12,
                                  color: _lightBlue,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1, color: _indigo),
              ],
            ),
          ),
        );
        if (box.maxWidth < 830) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [introduction, const SizedBox(height: 28), features],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 4, child: introduction),
            const SizedBox(width: 34),
            Expanded(flex: 6, child: features),
          ],
        );
      },
    ),
  );
}

class _Questions extends StatefulWidget {
  const _Questions();

  @override
  State<_Questions> createState() => _QuestionsState();
}

class _QuestionsState extends State<_Questions> {
  int? _open;

  static const _answerPadding = EdgeInsets.fromLTRB(5, 0, 5, 13);
  static const _panelPadding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 9,
  );

  static const _items = [
    (
      'Do I need to be a student?',
      'No. Students, independent creators, and reviewers can take part from anywhere.',
    ),
    (
      'What can I share?',
      'Share a link to a capstone, research project, prototype, game, or design. Make sure the people you invite can open it.',
    ),
    (
      'What is a review checklist?',
      'A review checklist, called a rubric in the workspace, lists what to check. Reviewers give each item a score and can explain their feedback.',
    ),
    (
      'Who can see my project?',
      'Keep it private, invite specific reviewers, or share it with signed-in members. Set permissions for linked files separately.',
    ),
  ];

  double _answerHeight(
    BuildContext context,
    String answer,
    TextStyle style,
    double width,
  ) {
    final defaults = DefaultTextStyle.of(context);
    final painter = TextPainter(
      text: TextSpan(text: answer, style: defaults.style.merge(style)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      textHeightBehavior: defaults.textHeightBehavior,
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width);
    final height = painter.height + _answerPadding.vertical;
    painter.dispose();
    return height;
  }

  Widget _accordion() => LayoutBuilder(
    builder: (context, box) {
      final answerStyle = _type(12, color: _indigo, height: 1.6);
      final width =
          (box.maxWidth - _panelPadding.horizontal - _answerPadding.horizontal)
              .clamp(0.0, double.infinity);
      final heights = [
        for (final (_, answer) in _items)
          _answerHeight(context, answer, answerStyle, width),
      ];
      final reserved = heights.reduce((a, b) => a > b ? a : b);
      final shown = _open == null ? 0.0 : heights[_open!];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSurface(
            dark: false,
            blur: 0,
            child: Padding(
              padding: _panelPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < _items.length; index++) ...[
                    if (index > 0) const Divider(height: 1, color: _rule),
                    Semantics(
                      expanded: _open == index,
                      child: TextButton(
                        onPressed: () => setState(
                          () => _open = _open == index ? null : index,
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 9,
                          ),
                          foregroundColor: _sapphire,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _items[index].$1,
                                style: _type(13, weight: 800),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              _open == index
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_open == index)
                      Padding(
                        padding: _answerPadding,
                        child: Text(_items[index].$2, style: answerStyle),
                      ),
                  ],
                ],
              ),
            ),
          ),
          // Use the space below the card so expanding an answer keeps the footer still.
          SizedBox(height: reserved - shown),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final stacked = box.maxWidth < 830;
      final heading = Semantics(
        header: true,
        child: Text('Common questions', style: _display(stacked ? 36 : 48)),
      );
      final questions = _accordion();
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [heading, const SizedBox(height: 22), questions],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: heading),
          const SizedBox(width: 34),
          Expanded(flex: 6, child: questions),
        ],
      );
    },
  );
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.child});

  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stopListening();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else if (_animation.isDismissed) {
      _position = Scrollable.maybeOf(context)?.position;
      _position?.addListener(_revealIfVisible);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealIfVisible();
      });
    }
  }

  void _stopListening() {
    _position?.removeListener(_revealIfVisible);
    _position = null;
  }

  void _revealIfVisible() {
    final position = _position;
    if (position == null || !position.haveDimensions) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    if (top > position.pixels + position.viewportDimension - 32 ||
        top + box.size.height < position.pixels) {
      return;
    }
    _stopListening();
    _animation.forward();
  }

  @override
  void dispose() {
    _stopListening();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_animation.value);
      if (progress == 1) return child!;
      return Transform.translate(
        offset: Offset(0, 21 * (1 - progress)),
        child: Opacity(opacity: .78 + .22 * progress, child: child),
      );
    },
  );
}
