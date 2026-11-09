import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

const _smartBlue = Color(0xFF0466C8);
const _sapphire = Color(0xFF0353A4);
const _regal = Color(0xFF023E7D);
const _prussian = Color(0xFF002855);
const _navy = Color(0xFF001845);
const _ink = Color(0xFF001233);
const _indigo = Color(0xFF33415C);
const _slate = Color(0xFF5C677D);
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
    Text(label, style: _type(11, color: color, weight: 800, spacing: 1.65));

Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.connected});

  final bool connected;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _top = GlobalKey();
  final _workflow = GlobalKey();
  final _audience = GlobalKey();
  final _trust = GlobalKey();
  final _faq = GlobalKey();

  void _go(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: _motion(context, 520),
      curve: Curves.easeInOutCubic,
    );
  }

  void _demo() => Navigator.pushNamed(context, '/demo');

  void _open() {
    if (widget.connected) {
      Navigator.pushNamed(context, '/workspace');
    } else {
      _demo();
    }
  }

  String get _startLabel => widget.connected ? 'Open workspace' : 'Open demo';

  @override
  Widget build(BuildContext context) {
    final links = [
      ('How it works', _workflow),
      ('Who it’s for', _audience),
      ('Trust & access', _trust),
      ('FAQ', _faq),
    ];

    return Scaffold(
      backgroundColor: _paper,
      body: SelectionArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                key: _top,
                color: _ink,
                child: _PageWidth(
                  child: LayoutBuilder(
                    builder: (context, box) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const _Wordmark(),
                          const Spacer(),
                          if (box.maxWidth >= 830) ...[
                            for (final (label, target) in links)
                              _TextAction(
                                label,
                                dark: true,
                                onPressed: () => _go(target),
                              ),
                            const SizedBox(width: 18),
                          ],
                          if (box.maxWidth < 830)
                            PopupMenuButton<GlobalKey>(
                              tooltip: 'Navigate landing page',
                              icon: const Icon(
                                Icons.menu_rounded,
                                color: Colors.white,
                              ),
                              onSelected: _go,
                              itemBuilder: (context) => [
                                for (final (label, target) in links)
                                  PopupMenuItem(
                                    value: target,
                                    child: Text(label, style: _type(14)),
                                  ),
                              ],
                            ),
                          if (box.maxWidth >= 295)
                            _Action(
                              widget.connected ? 'Sign in' : 'Open demo',
                              onPressed: _open,
                              secondary: true,
                              dark: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _PageWidth(
                child: _Section(
                  child: _Hero(
                    startLabel: _startLabel,
                    onStart: _open,
                    onSteps: () => _go(_workflow),
                  ),
                ),
              ),
              const _ProjectTypes(),
              _PageWidth(
                key: _workflow,
                child: const _Section(child: _Workflow()),
              ),
              ColoredBox(
                key: _audience,
                color: _mist,
                child: _PageWidth(
                  child: _Section(
                    child: _Audience(startLabel: _startLabel, onStart: _open),
                  ),
                ),
              ),
              ColoredBox(
                key: _trust,
                color: _ink,
                child: const _PageWidth(child: _Section(child: _Trust())),
              ),
              _PageWidth(
                key: _faq,
                child: const _Section(child: _Questions()),
              ),
              ColoredBox(
                color: _navy,
                child: _PageWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Section(
                        child: _Reveal(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _eyebrow('OPEN THE WORKSPACE', color: _lightBlue),
                              const SizedBox(height: 16),
                              Semantics(
                                header: true,
                                child: Text(
                                  'What are you working on?',
                                  style: _display(52, color: Colors.white),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Bring a project you want to improve, or review a sample to see how EvaLink works.',
                                style: _type(16, color: _lightBlue),
                              ),
                              const SizedBox(height: 25),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  _Action(
                                    _startLabel,
                                    onPressed: _open,
                                    icon: Icons.arrow_outward_rounded,
                                  ),
                                  if (widget.connected)
                                    _Action(
                                      'Try the demo',
                                      onPressed: _demo,
                                      secondary: true,
                                      dark: true,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(color: _indigo, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 10,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const _Wordmark(),
                            Wrap(
                              spacing: 10,
                              children: [
                                _TextAction(
                                  'Demo',
                                  dark: true,
                                  onPressed: _demo,
                                ),
                                _TextAction(
                                  'Back to top',
                                  dark: true,
                                  onPressed: () => _go(_top),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageWidth extends StatelessWidget {
  const _PageWidth({super.key, required this.child});

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

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox.square(
        dimension: 38,
        child: CustomPaint(painter: _BrandGlyph()),
      ),
      const SizedBox(width: 10),
      Text(
        'EvaLink',
        style: _type(24, color: Colors.white, weight: 800, spacing: -1.1),
      ),
    ],
  );
}

class _BrandGlyph extends CustomPainter {
  const _BrandGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 64, 64),
        const Radius.circular(15),
      ),
      Paint()..color = _smartBlue,
    );
    final link = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(29, 18)
        ..lineTo(15, 32)
        ..lineTo(29, 46),
      link..color = Colors.white,
    );
    canvas.drawPath(
      Path()
        ..moveTo(35, 18)
        ..lineTo(49, 32)
        ..lineTo(35, 46),
      link..color = _lightBlue,
    );
    canvas.drawPath(
      Path()
        ..moveTo(26, 32)
        ..lineTo(31, 37)
        ..lineTo(39, 27),
      link..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandGlyph oldDelegate) => false;
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
        if (secondary) {
          return hover ? (dark ? _prussian : _mist) : Colors.transparent;
        }
        return hover ? _sapphire : _smartBlue;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return (dark || !secondary ? Colors.white : _smartBlue).withValues(
            alpha: .18,
          );
        }
        return null;
      }),
      textStyle: WidgetStatePropertyAll(_type(13, weight: 800)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 17, vertical: 11),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
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
      textStyle: _type(13, weight: 800),
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(label),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.startLabel,
    required this.onStart,
    required this.onSteps,
  });

  final String startLabel;
  final VoidCallback onStart;
  final VoidCallback onSteps;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final headingSize = wide
          ? (box.maxWidth * .058).clamp(51.0, 74.0)
          : (box.maxWidth * .112).clamp(37.0, 68.0);
      final intro = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 19, height: 2, color: _smartBlue),
              const SizedBox(width: 10),
              Expanded(child: _eyebrow('THE PROJECT REVIEW WORKSPACE')),
            ],
          ),
          const SizedBox(height: 22),
          Semantics(
            header: true,
            child: Text.rich(
              TextSpan(
                text: 'Bring your work.\n',
                children: [
                  TextSpan(
                    text: 'Get it reviewed.',
                    style: TextStyle(color: _sapphire),
                  ),
                ],
              ),
              style: _display(headingSize),
            ),
          ),
          const SizedBox(height: 21),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              'EvaLink connects students and independent creators with people who can test and evaluate their work. Share a project, invite evaluators, and get feedback you can use in your next revision.',
              style: _type(wide ? 17 : 16, color: _indigo, height: 1.65),
            ),
          ),
          const SizedBox(height: 27),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Action(
                startLabel,
                onPressed: onStart,
                icon: Icons.arrow_outward_rounded,
              ),
              _Action(
                'How it works',
                onPressed: onSteps,
                secondary: true,
                icon: Icons.south_rounded,
              ),
            ],
          ),
        ],
      );
      return wide
          ? Row(
              children: [
                Expanded(flex: 9, child: intro),
                const SizedBox(width: 44),
                const Expanded(flex: 11, child: _Reveal(child: _HeroPhoto())),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                intro,
                const SizedBox(height: 31),
                const _Reveal(child: _HeroPhoto()),
              ],
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
      final wide = box.maxWidth >= 475;
      final height = (box.maxWidth * .81).clamp(280.0, 520.0);
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          height: height + 32,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: wide ? 29 : 0,
                right: 0,
                bottom: 31,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _Photo(
                        asset: 'team-study',
                        description:
                            'Students discussing work around a study table',
                        alignment: Alignment(0, -.20),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [.3, 1],
                            colors: [Colors.transparent, Color(0xC4001233)],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 18,
                        bottom: wide ? 24 : 75,
                        child: _eyebrow(
                          'PROJECT COLLABORATION',
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: wide ? 0 : 12,
                bottom: 0,
                width: (box.maxWidth - 24).clamp(0.0, 335.0),
                child: AnimatedSlide(
                  offset: _hovered && !MediaQuery.disableAnimationsOf(context)
                      ? const Offset(.024, -.07)
                      : Offset.zero,
                  duration: _motion(context, 280),
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _rule),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22001233),
                          blurRadius: 22,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          const _IconTile(Icons.rate_review_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _eyebrow('SAMPLE FEEDBACK'),
                                const SizedBox(height: 3),
                                Text(
                                  'Clarify what happens after submitting the form.',
                                  style: _type(13, weight: 700, height: 1.4),
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
      );
    },
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
      color: Colors.white,
      border: Border.symmetric(horizontal: BorderSide(color: _rule)),
    ),
    child: _PageWidth(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 21),
        child: Wrap(
          spacing: 30,
          runSpacing: 13,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _eyebrow('WHAT YOU CAN REVIEW', color: _slate),
            for (final (icon, label) in const [
              (Icons.school_outlined, 'Capstones & research'),
              (Icons.view_in_ar_outlined, 'Apps & prototypes'),
              (Icons.sports_esports_outlined, 'Games & playtests'),
              (Icons.draw_outlined, 'Design & creative work'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: _sapphire),
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, style: _type(13, weight: 800))),
                ],
              ),
          ],
        ),
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
              box.maxWidth < 530 ? 40 : 54,
              color: dark ? Colors.white : _ink,
            ),
          ),
        ),
        const SizedBox(height: 15),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 535),
          child: Text(
            body,
            style: _type(16, color: dark ? _lightBlue : _indigo),
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
      title: 'Share the work',
      detail:
          'Add a short brief and a link to your project. Choose a rubric so reviewers know what to assess.',
      icon: Icons.layers_outlined,
      panel: 'Project brief',
      example: 'Test the appointment flow on mobile.',
      rows: [
        ('Project type', 'App prototype'),
        ('Evaluation rubric', 'Usability'),
        ('Project visibility', 'Private'),
      ],
    ),
    (
      title: 'Invite an evaluator',
      detail:
          'Browse the directory for a relevant perspective and send a review request. Evaluators can accept or decline.',
      icon: Icons.person_add_alt_outlined,
      panel: 'Review invitation',
      example: 'Try to book an appointment as a first-time visitor.',
      rows: [
        ('Perspective', 'Usability reviewer'),
        ('Review focus', 'First-time experience'),
        ('Invitation status', 'Accepted'),
      ],
    ),
    (
      title: 'Read the feedback',
      detail:
          'See rubric scores and written observations together so you can decide what to improve in the next version.',
      icon: Icons.rate_review_outlined,
      panel: 'Review results',
      example: 'Show a confirmation screen after booking.',
      rows: [
        ('Ease of use', '4 / 5'),
        ('Clarity', '3 / 5'),
        ('Suggested change', 'Confirm next steps'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_selected];
    return _Reveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            label: 'HOW IT WORKS',
            title: 'From a first draft to a better one.',
            body:
                'Follow one sample project through the three steps of an EvaLink review.',
          ),
          const SizedBox(height: 31),
          LayoutBuilder(
            builder: (context, box) {
              final stacked = box.maxWidth < 810;
              final buttons = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _StepButton(
                        number: i + 1,
                        title: _steps[i].title,
                        detail: _steps[i].detail,
                        selected: i == _selected,
                        onPressed: () => _select(i, revealSample: stacked),
                      ),
                    ),
                ],
              );
              final sample = _ReviewSample(
                key: _sample,
                step: _selected,
                panel: step.panel,
                icon: step.icon,
                example: step.example,
                rows: step.rows,
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [buttons, const SizedBox(height: 15), sample],
                );
              }
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
          selected ? _mist : Colors.white,
        ),
        foregroundColor: const WidgetStatePropertyAll(_sapphire),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(15)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 66)),
        alignment: Alignment.centerLeft,
        animationDuration: _motion(context, 160),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          Text('0$number', style: _type(12, color: _sapphire, weight: 800)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _type(17, weight: 800)),
                if (selected) ...[
                  const SizedBox(height: 6),
                  Text(detail, style: _type(14, color: _indigo)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 9),
          Icon(
            selected ? Icons.arrow_forward_rounded : Icons.add_rounded,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class _ReviewSample extends StatelessWidget {
  const _ReviewSample({
    super.key,
    required this.step,
    required this.panel,
    required this.icon,
    required this.example,
    required this.rows,
  });

  final int step;
  final String panel;
  final IconData icon;
  final String example;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 455;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: _prussian,
          child: CustomPaint(
            painter: const _Grid(),
            child: Padding(
              padding: EdgeInsets.all(compact ? 16 : 29),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _eyebrow('SAMPLE PROJECT', color: _lightBlue),
                      Text(
                        '0${step + 1} / 03',
                        style: _type(
                          12,
                          color: Colors.white,
                          weight: 800,
                          spacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: _motion(context, 260),
                    switchInCurve: Curves.easeOutCubic,
                    layoutBuilder: (current, _) =>
                        current ?? const SizedBox.shrink(),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: animation.drive(
                          Tween(begin: const Offset(.025, 0), end: Offset.zero),
                        ),
                        child: child,
                      ),
                    ),
                    child: Container(
                      key: ValueKey(step),
                      width: double.infinity,
                      padding: EdgeInsets.all(compact ? 16 : 23),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _IconTile(icon),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _eyebrow(panel.toUpperCase()),
                                      Text(
                                        'Campus Clinic',
                                        style: _type(
                                          23,
                                          weight: 800,
                                          spacing: -.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Text(example, style: _type(15, color: _indigo)),
                            const SizedBox(height: 15),
                            for (final (label, value) in rows) ...[
                              const Divider(height: 1, color: _rule),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: _type(13, color: _slate),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        value,
                                        textAlign: TextAlign.end,
                                        style: _type(13, weight: 800),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
      );
    },
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
  const _Audience({required this.startLabel, required this.onStart});

  final String startLabel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => _Reveal(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          label: 'WHO IT’S FOR',
          title: 'Two sides of a good review.',
          body:
              'Creators bring the work and the questions. Evaluators bring practical experience, domain knowledge, or a fresh pair of eyes.',
        ),
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, box) {
            const creator = _AudienceCard(
              number: '01',
              label: 'FOR STUDENTS & CREATORS',
              title: 'Know what to improve.',
              detail:
                  'Prepare for a capstone presentation, test an early prototype, or learn where people get stuck in your game. Use the review to decide what to change before you share it more widely.',
              photo: 'creator-notes',
              description: 'A student making notes beside a laptop',
            );
            const reviewer = _AudienceCard(
              number: '02',
              label: 'FOR EVALUATORS',
              title: 'Bring your perspective.',
              detail:
                  'Review as a peer, practitioner, subject-matter expert, or a first-time user. Follow the project brief and rubric, then explain what worked and where the creator can make a change.',
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
        const SizedBox(height: 21),
        _TextAction(startLabel, onPressed: onStart),
      ],
    ),
  );
}

class _AudienceCard extends StatelessWidget {
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _rule),
      borderRadius: BorderRadius.circular(14),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2.15,
            child: _Photo(asset: photo, description: description),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _eyebrow('$number   /   $label'),
                const SizedBox(height: 9),
                Semantics(
                  header: true,
                  child: Text(title, style: _display(32)),
                ),
                const SizedBox(height: 10),
                Text(detail, style: _type(15, color: _indigo, height: 1.6)),
              ],
            ),
          ),
        ],
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
      'Understand evaluator profiles',
      'Evaluator expertise and portfolio links are self-reported. Use the profile to see whether the person has a perspective that fits your project.',
    ),
    (
      Icons.fact_check_outlined,
      'Set expectations for reviews',
      'Evaluators declare conflicts of interest when submitting a review. Signed-in members can report community projects for moderation.',
    ),
  ];

  @override
  Widget build(BuildContext context) => _Reveal(
    child: LayoutBuilder(
      builder: (context, box) {
        const introduction = _SectionTitle(
          label: 'TRUST & ACCESS',
          title: 'Share with intention.',
          body: 'Decide who can see the work and what you want them to assess.',
          dark: true,
        );
        final features = Column(
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
                            style: _type(17, color: Colors.white, weight: 800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            style: _type(14, color: _lightBlue, height: 1.6),
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

class _Questions extends StatelessWidget {
  const _Questions();

  static const _items = [
    (
      'Do I need a school affiliation?',
      'EvaLink is for student teams and independent creators, as well as peers and professionals who want to review projects remotely.',
    ),
    (
      'What can I submit?',
      'You can share research, a capstone, a playable build, a design, or another project using an HTTPS link that your invited reviewers can access.',
    ),
    (
      'What is a rubric?',
      'A rubric is a list of things to assess, such as clarity or ease of use. Reviewers use the same criteria and can explain their scores in writing.',
    ),
    (
      'Can I try it before creating an account?',
      'Yes. The demo uses fictional projects and evaluators, so you can explore the workspace and try the review flow.',
    ),
  ];

  @override
  Widget build(BuildContext context) => _Reveal(
    child: LayoutBuilder(
      builder: (context, box) {
        const heading = _SectionTitle(
          label: 'FAQ',
          title: 'A few things to know.',
          body: 'The basics before you share a project or start reviewing.',
        );
        final questions = Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Column(
            children: [
              for (final (question, answer) in _items) ...[
                const Divider(height: 1, color: _rule),
                ExpansionTile(
                  title: Text(question, style: _type(15, weight: 800)),
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(4, 0, 23, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  iconColor: _sapphire,
                  collapsedIconColor: _sapphire,
                  expansionAnimationStyle:
                      MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : const AnimationStyle(
                          duration: Duration(milliseconds: 220),
                        ),
                  children: [
                    Text(answer, style: _type(14, color: _indigo, height: 1.6)),
                  ],
                ),
              ],
              const Divider(height: 1, color: _rule),
            ],
          ),
        );
        if (box.maxWidth < 830) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 22), questions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 4, child: heading),
            const SizedBox(width: 34),
            Expanded(flex: 6, child: questions),
          ],
        );
      },
    ),
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
