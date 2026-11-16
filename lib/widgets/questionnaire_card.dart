import 'package:flutter/material.dart';

import '../app_theme.dart';

class QuestionnaireCard extends StatelessWidget {
  const QuestionnaireCard({
    super.key,
    required this.child,
    this.header = false,
  });
  final Widget child;
  final bool header;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: workshopNight.withValues(alpha: .43),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: workshopEdge),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header)
          const SizedBox(height: 6, child: ColoredBox(color: workshopIce)),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ],
    ),
  );
}
