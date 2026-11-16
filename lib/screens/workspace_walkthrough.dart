import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../widgets/app_notice.dart';

enum WalkthroughStep {
  overview(
    'Find your work',
    'Your overview brings recent projects, review requests, and feedback together.',
  ),
  create(
    'Create a project',
    'Click New project to try the real form with an example brief, testing instructions, and a questionnaire.',
    'Try New project',
  ),
  publish(
    'Post to the community',
    'Open the highlighted project, then choose Share with community. This practice project stays in the tour.',
    'Open practice project',
  ),
  evaluate(
    'Evaluate a community project',
    'Click Evaluate to try rating a question and leaving feedback on a practice project.',
    'Try Evaluate',
  ),
  results(
    'Read evaluation responses',
    'Click Responses to see ratings and written feedback. Open a review group to see individual responses.',
    'Try Responses',
  ),
  templates(
    'Find reusable questionnaires',
    'Use Preview to inspect a template. In your own workspace, Edit a copy lets you customize and save it for future projects.',
    'Preview template',
  );

  const WalkthroughStep(this.title, this.detail, [this.action]);
  final String title, detail;
  final String? action;
}

class WorkspaceWalkthrough extends StatelessWidget {
  const WorkspaceWalkthrough({
    super.key,
    required this.step,
    required this.target,
    required this.busy,
    required this.back,
    required this.next,
    required this.skip,
    this.tryControl,
    this.error,
  });

  final WalkthroughStep step;
  final Rect? target;
  final bool busy;
  final VoidCallback? back, tryControl;
  final VoidCallback next, skip;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final corePractice =
        step == WalkthroughStep.create || step == WalkthroughStep.evaluate;
    return WalkthroughSpotlight(
      target: target,
      label:
          'Workspace tour · ${step.index + 1} of ${WalkthroughStep.values.length}',
      title: step.title,
      detail: step.detail,
      busy: busy,
      back: back,
      next: corePractice ? tryControl! : next,
      nextLabel: corePractice
          ? step.action!
          : step == WalkthroughStep.values.last
          ? 'Finish tour'
          : 'Next',
      alternateLabel: corePractice ? 'Skip practice' : step.action,
      alternate: corePractice ? next : tryControl,
      skip: skip,
      allowTarget: tryControl != null,
      error: error,
    );
  }
}

class WalkthroughSpotlight extends StatelessWidget {
  const WalkthroughSpotlight({
    super.key,
    required this.target,
    required this.label,
    required this.title,
    required this.detail,
    required this.nextLabel,
    required this.next,
    required this.skip,
    this.skipLabel = 'Skip tour',
    this.back,
    this.alternateLabel,
    this.alternate,
    this.allowTarget = false,
    this.formGuide = false,
    this.busy = false,
    this.error,
  });

  final Rect? target;
  final String label, title, detail, nextLabel, skipLabel;
  final String? alternateLabel, error;
  final VoidCallback next, skip;
  final VoidCallback? back, alternate;
  final bool allowTarget, formGuide, busy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Offset.zero & constraints.biggest;
      final target = this.target?.intersect(viewport);
      final visible = target != null && !target.isEmpty ? target : null;
      final highlight = visible?.inflate(5).intersect(viewport);
      final hit = !busy && allowTarget ? visible : null;
      final blockers = formGuide
          ? const <Rect>[]
          : hit == null
          ? [viewport]
          : [
              Rect.fromLTRB(0, 0, viewport.right, hit.top),
              Rect.fromLTRB(0, hit.bottom, viewport.right, viewport.bottom),
              Rect.fromLTRB(0, hit.top, hit.left, hit.bottom),
              Rect.fromLTRB(hit.right, hit.top, viewport.right, hit.bottom),
            ];
      return Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _Spotlight(highlight, formGuide: formGuide),
            ),
          ),
          for (final rect in blockers)
            if (!rect.isEmpty)
              Positioned.fromRect(rect: rect, child: const AbsorbPointer()),
          CustomMultiChildLayout(
            delegate: _CalloutLayout(
              highlight,
              MediaQuery.paddingOf(context),
              preferSide: formGuide,
            ),
            children: [
              if (highlight != null)
                LayoutId(
                  id: _CalloutPart.arrow,
                  child: const IgnorePointer(child: _Arrow()),
                ),
              LayoutId(
                id: _CalloutPart.card,
                child: FocusScope(
                  key: ValueKey(title),
                  child: CallbackShortcuts(
                    bindings: {
                      if (!busy)
                        const SingleActivator(LogicalKeyboardKey.escape): skip,
                    },
                    child: _callout(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  Widget _callout(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: workshopSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: _calloutEdge),
      ),
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(15, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: text.labelLarge?.copyWith(color: workshopIce),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : skip,
                  child: Text(skipLabel),
                ),
              ],
            ),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 5),
            Text(detail, style: text.bodySmall?.copyWith(color: workshopMuted)),
            if (error case final message?) ...[
              const SizedBox(height: 8),
              AppNotice(message, tone: NoticeTone.error),
            ],
            const SizedBox(height: 6),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 4,
              children: [
                if (back != null)
                  TextButton(
                    onPressed: busy ? null : back,
                    child: const Text('Back'),
                  ),
                if (alternate != null)
                  TextButton(
                    onPressed: busy ? null : alternate,
                    child: Text(alternateLabel!),
                  ),
                FilledButton(
                  autofocus: !formGuide,
                  onPressed: busy ? null : next,
                  child: Text(busy ? 'Saving…' : nextLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _calloutEdge = Color(0xFF526884);

class _Spotlight extends CustomPainter {
  const _Spotlight(this.target, {required this.formGuide});

  final Rect? target;
  final bool formGuide;

  @override
  void paint(Canvas canvas, Size size) {
    if (target == null && formGuide) return;
    final cutout = target == null
        ? null
        : RRect.fromRectAndRadius(target!, const Radius.circular(10));
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (cutout != null) mask.addRRect(cutout);
    canvas.drawPath(
      mask,
      Paint()
        ..color = formGuide ? const Color(0x73040811) : const Color(0xB6040811),
    );
    if (cutout != null) {
      canvas.drawRRect(
        cutout.inflate(2),
        Paint()
          ..color = workshopIce.withValues(alpha: .16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      canvas.drawRRect(
        cutout,
        Paint()
          ..color = workshopIce
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_Spotlight oldDelegate) =>
      target != oldDelegate.target || formGuide != oldDelegate.formGuide;
}

enum _CalloutPart { card, arrow }

class _CalloutLayout extends MultiChildLayoutDelegate {
  _CalloutLayout(this.anchor, this.safeArea, {required this.preferSide});

  final Rect? anchor;
  final EdgeInsets safeArea;
  final bool preferSide;

  @override
  void performLayout(Size size) {
    const margin = 12.0;
    const gap = 13.0;
    final screen = (Offset.zero & size).deflate(margin);
    final safe = safeArea.deflateRect(screen);
    final width = math.max(0.0, math.min(352.0, safe.width));
    final rect = anchor;
    final right = rect != null && safe.right - rect.right >= width + gap;
    final leftOfTarget = rect != null && rect.left - safe.left >= width + gap;
    final beside = preferSide && (right || leftOfTarget);
    final above = rect == null ? 0.0 : rect.top - safe.top - gap;
    final below = rect == null ? 0.0 : safe.bottom - rect.bottom - gap;
    final card = layoutChild(
      _CalloutPart.card,
      BoxConstraints.tightFor(width: width).copyWith(
        maxHeight: math.max(
          0,
          rect == null || beside ? safe.height : math.max(above, below),
        ),
      ),
    );
    if (rect == null) {
      positionChild(
        _CalloutPart.card,
        safe.center - Offset(card.width / 2, card.height / 2),
      );
      return;
    }

    const arrow = 11.0;
    layoutChild(
      _CalloutPart.arrow,
      const BoxConstraints.tightFor(width: arrow, height: arrow),
    );
    if (beside) {
      final left = right ? rect.right + gap : rect.left - gap - card.width;
      final top = (rect.center.dy - card.height / 2)
          .clamp(safe.top, math.max(safe.top, safe.bottom - card.height))
          .toDouble();
      positionChild(_CalloutPart.card, Offset(left, top));
      final pointer = rect.center.dy.clamp(
        top + 17,
        math.max(top + 17, top + card.height - 17),
      );
      positionChild(
        _CalloutPart.arrow,
        Offset(
          (right ? left : left + card.width) - arrow / 2,
          pointer - arrow / 2,
        ),
      );
      return;
    }
    final placeBelow = below >= card.height || below >= above;
    final left = (rect.center.dx - card.width / 2).clamp(
      safe.left,
      safe.right - card.width,
    );
    final top = placeBelow ? rect.bottom + gap : rect.top - gap - card.height;
    positionChild(_CalloutPart.card, Offset(left, top));

    final pointer = rect.center.dx.clamp(
      left + 17,
      math.max(left + 17, left + card.width - 17),
    );
    positionChild(
      _CalloutPart.arrow,
      Offset(
        pointer - arrow / 2,
        (placeBelow ? top : top + card.height) - arrow / 2,
      ),
    );
  }

  @override
  bool shouldRelayout(_CalloutLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      safeArea != oldDelegate.safeArea ||
      preferSide != oldDelegate.preferSide;
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi / 4,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        color: workshopSurface,
        border: Border.fromBorderSide(BorderSide(color: _calloutEdge)),
      ),
      child: SizedBox.expand(),
    ),
  );
}
