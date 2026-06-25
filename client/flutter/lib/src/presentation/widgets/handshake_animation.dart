import 'dart:async';

import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/motion.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// The one expressive motion moment in the app: session establishment.
///
/// Two nodes converge while the key-derivation steps tick through
/// (k_sig → k_mac → SAS) and the status dot moves amber → green once the
/// channel is actually up. Tap anywhere to skip the choreography; it never
/// gates the connection itself — [onFinished] fires as soon as both the
/// animation (or its skip) and the real connection are done.
class HandshakeAnimation extends StatefulWidget {
  const HandshakeAnimation({
    super.key,
    required this.connected,
    this.waitingMessage = 'Establishing encrypted channel',
    this.onFinished,
  });

  /// Whether the underlying transport is actually connected.
  final bool connected;

  /// Status text shown while the channel is still coming up.
  final String waitingMessage;

  /// Called once, shortly after the choreography completes and
  /// [connected] is true.
  final VoidCallback? onFinished;

  @override
  State<HandshakeAnimation> createState() => _HandshakeAnimationState();
}

class _HandshakeAnimationState extends State<HandshakeAnimation>
    with TickerProviderStateMixin {
  static const double _stageWidth = 280;
  static const double _stageHeight = 32;
  static const _steps = [
    ('k_sig', 'signing key derived'),
    ('k_mac', 'authentication key derived'),
    ('sas', 'short authentication string ready'),
  ];
  static const _stepThresholds = [0.30, 0.55, 0.80];

  late final AnimationController _choreo;
  late final AnimationController _pulse;
  Timer? _finishTimer;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _choreo = AnimationController(vsync: this, duration: AppMotion.handshake)
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _maybeFinish();
        }
      })
      ..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.4,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(HandshakeAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !oldWidget.connected) {
      _maybeFinish();
    }
  }

  void _maybeFinish() {
    if (_notified || !widget.connected || !_choreo.isCompleted) return;
    _notified = true;
    _finishTimer = Timer(const Duration(milliseconds: 350), () {
      widget.onFinished?.call();
    });
  }

  void _skip() {
    if (!_choreo.isCompleted) {
      _choreo.value = 1;
      _maybeFinish();
    }
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _choreo.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppMotion.easing.transform(_choreo.value);
    final done = widget.connected && _choreo.isCompleted;
    final dotColor = done ? AppColors.ok : AppColors.warn;
    final statusText = done
        ? 'E2EE ESTABLISHED'
        : widget.waitingMessage.toUpperCase();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _stageWidth,
              height: _stageHeight,
              child: CustomPaint(painter: _NodesPainter(progress: t)),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: _stageWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedOpacity(
                      opacity: t >= _stepThresholds[i] ? 1 : 0,
                      duration: AppMotion.standard,
                      curve: AppMotion.easing,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Text(
                              _steps[i].$1,
                              style: AppTypography.data.copyWith(
                                color: AppColors.info,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _steps[i].$2,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                done
                    ? Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.ok,
                          shape: BoxShape.circle,
                        ),
                      )
                    : FadeTransition(
                        opacity: _pulse,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.warn,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  statusText,
                  style: AppTypography.caption.copyWith(color: dotColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NodesPainter extends CustomPainter {
  _NodesPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const nodeRadius = 4.0;
    const meetGap = 36.0;

    final leftX = _lerp(nodeRadius, size.width / 2 - meetGap, progress);
    final rightX = _lerp(
      size.width - nodeRadius,
      size.width / 2 + meetGap,
      progress,
    );

    // The link draws in once the nodes are nearly in place.
    final linkT = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
    if (linkT > 0) {
      final mid = size.width / 2;
      final half = (rightX - leftX) / 2 * linkT;
      canvas.drawLine(
        Offset(mid - half, cy),
        Offset(mid + half, cy),
        Paint()
          ..color = AppColors.borderStrong
          ..strokeWidth = 1,
      );
    }

    final nodePaint = Paint()..color = AppColors.textPrimary;
    canvas.drawCircle(Offset(leftX, cy), nodeRadius, nodePaint);
    canvas.drawCircle(Offset(rightX, cy), nodeRadius, nodePaint);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_NodesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
