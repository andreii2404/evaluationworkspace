import 'package:flutter/material.dart';

class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true, count: 4);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: widget.label,
    excludeSemantics: true,
    child: RepaintBoundary(
      child: FadeTransition(
        opacity: _pulse.drive(
          Tween(
            begin: .48,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeInOut)),
        ),
        child: widget.child,
      ),
    ),
  );
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.radius = 8,
  });

  final double height, radius;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: width,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    required this.label,
    this.count = 3,
    this.leading = false,
  });

  final String label;
  final int count;
  final bool leading;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    label: label,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < count; index++)
          Padding(
            padding: EdgeInsets.only(bottom: index + 1 == count ? 0 : 15),
            child: Row(
              children: [
                if (leading) ...[
                  const SkeletonBlock(height: 34, width: 34, radius: 17),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    children: [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: index.isEven ? .68 : .52,
                        child: const SkeletonBlock(height: 12),
                      ),
                      const SizedBox(height: 8),
                      const FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: .40,
                        child: SkeletonBlock(height: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
