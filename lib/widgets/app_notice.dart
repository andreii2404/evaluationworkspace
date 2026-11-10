import 'dart:math' as math;

import 'package:flutter/material.dart';

enum NoticeTone {
  info(Icons.info_outline, Color(0xFFB9D9FF)),
  success(Icons.check_circle_outline, Color(0xFFB8EFDC)),
  error(Icons.error_outline, Color(0xFFFFC8CC));

  const NoticeTone(this.icon, this.accent);
  final IconData icon;
  final Color accent;

  RoundedRectangleBorder get shape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(15),
    side: BorderSide(color: accent.withValues(alpha: .42)),
  );
}

/// The same status treatment for transient feedback and in-form errors.
class AppNotice extends StatelessWidget {
  const AppNotice(this.message, {super.key, this.tone = NoticeTone.info});

  final String message;
  final NoticeTone tone;
  static const _surface = Color(0xFF172332);

  static void show(
    BuildContext context,
    String message, {
    NoticeTone tone = NoticeTone.info,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: math.min(416, MediaQuery.sizeOf(context).width * .91),
          backgroundColor: _surface,
          shape: tone.shape,
          elevation: 8,
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          showCloseIcon: true,
          closeIconColor: const Color(0xFFD0DCEC),
          duration: Duration(
            seconds: MediaQuery.accessibleNavigationOf(context)
                ? 12
                : tone == NoticeTone.error
                ? 7
                : 4,
          ),
          content: _NoticeContent(message, tone),
        ),
        snackBarAnimationStyle: reduceMotion
            ? AnimationStyle.noAnimation
            : null,
      );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: ShapeDecoration(color: _surface, shape: tone.shape),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _NoticeContent(message, tone),
      ),
    ),
  );
}

class _NoticeContent extends StatelessWidget {
  const _NoticeContent(this.message, this.tone);
  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(tone.icon, size: 17, color: tone.accent),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F7FC),
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}
