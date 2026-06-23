import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// Decorative dot lattice on the app background — the "visible grid logic"
/// of setup surfaces. Applied only behind pre-session content (onboarding,
/// launcher, pairing, handshake); never behind a live session, video, or
/// overlay panels. Cards and banners occlude it, so it reads only in the
/// negative space around content.
class DotGridBackground extends StatelessWidget {
  final Widget child;

  const DotGridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: RepaintBoundary(
        child: CustomPaint(painter: const _DotGridPainter(), child: child),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = AppUiMetrics.dotGridDotSize
      ..strokeCap = StrokeCap.round;

    const pitch = AppUiMetrics.dotGridPitch;
    const inset = pitch / 2;
    final points = <Offset>[
      for (var y = inset; y < size.height; y += pitch)
        for (var x = inset; x < size.width; x += pitch) Offset(x, y),
    ];
    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}
