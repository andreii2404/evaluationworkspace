import 'package:flutter/material.dart';

import 'workspace_walkthrough.dart';

class PracticeTip {
  const PracticeTip(this.target, this.title, this.detail);

  final GlobalKey target;
  final String title;
  final String detail;
}

class PracticeFormGuide extends StatefulWidget {
  const PracticeFormGuide({
    super.key,
    required this.label,
    required this.tips,
    required this.total,
    required this.child,
    this.offset = 0,
    this.advance,
    this.advanceLabel = 'Done',
  });

  final String label;
  final List<PracticeTip> tips;
  final int offset, total;
  final VoidCallback? advance;
  final String advanceLabel;
  final Widget child;

  @override
  State<PracticeFormGuide> createState() => _PracticeFormGuideState();
}

class _PracticeFormGuideState extends State<PracticeFormGuide> {
  final _viewport = GlobalKey();
  int _index = 0;
  Rect? _bounds;
  bool _hidden = false;
  bool _reveal = true;
  bool _measureQueued = false;

  @override
  void didUpdateWidget(PracticeFormGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offset == widget.offset) return;
    _index = oldWidget.offset < widget.offset ? 0 : widget.tips.length - 1;
    _bounds = null;
    _reveal = true;
  }

  void _measure() {
    if (_hidden || _measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted || _hidden) return;
      final anchor = widget.tips[_index].target.currentContext;
      final target = anchor?.findRenderObject();
      final viewport = _viewport.currentContext?.findRenderObject();
      if (anchor == null ||
          target is! RenderBox ||
          viewport is! RenderBox ||
          !target.hasSize ||
          !viewport.hasSize) {
        return;
      }

      final size = Offset.zero & viewport.size;
      final scrollable = Scrollable.maybeOf(anchor);
      final scrollBox = scrollable?.context.findRenderObject();
      final clip = scrollBox is RenderBox && scrollBox.hasSize
          ? size.intersect(
              scrollBox.localToGlobal(Offset.zero, ancestor: viewport) &
                  scrollBox.size,
            )
          : size;
      final targetBounds =
          target.localToGlobal(Offset.zero, ancestor: viewport) & target.size;
      final visible = targetBounds.intersect(clip);
      if (_reveal) {
        _reveal = false;
        if (scrollable != null && visible.size != targetBounds.size) {
          Scrollable.ensureVisible(anchor, alignment: .18);
          _measure();
        }
      }
      final bounds = visible.isEmpty ? null : visible;
      if (bounds != _bounds) setState(() => _bounds = bounds);
    });
  }

  void _goTo(int index) => setState(() {
    _index = index;
    _bounds = null;
    _reveal = true;
  });

  void _hide() => setState(() => _hidden = true);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _measure();
      final tip = widget.tips[_index];
      final last = _index == widget.tips.length - 1;
      return Stack(
        key: _viewport,
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _measure();
              return false;
            },
            child: widget.child,
          ),
          if (!_hidden && MediaQuery.viewInsetsOf(context).bottom == 0)
            WalkthroughSpotlight(
              target: _bounds,
              label:
                  '${widget.label} · ${widget.offset + _index + 1} of ${widget.total}',
              title: tip.title,
              detail: tip.detail,
              nextLabel: last ? widget.advanceLabel : 'Next tip',
              next: last ? widget.advance ?? _hide : () => _goTo(_index + 1),
              back: _index == 0 ? null : () => _goTo(_index - 1),
              skip: _hide,
              skipLabel: 'Hide tips',
              formGuide: true,
            ),
        ],
      );
    },
  );
}
