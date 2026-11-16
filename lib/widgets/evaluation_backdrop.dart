import 'package:flutter/material.dart';

import '../app_theme.dart';

class EvaluationBackdrop extends StatelessWidget {
  const EvaluationBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) {
      return const ColoredBox(color: workshopNight);
    }
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: workshopNight,
          gradient: RadialGradient(
            center: Alignment(.74, -.9),
            radius: 1.12,
            colors: [Color(0xFF292A46), Color(0xFF161B2C), workshopNight],
            stops: [0, .45, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1, .88),
              radius: .8,
              colors: [Color(0x60373E68), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
