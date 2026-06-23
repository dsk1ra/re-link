import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/motion.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// Invite expiry countdown: mono caption over a 2px progress track.
/// Pulses gently in the warn colour as it approaches zero.
class AppTtlTimer extends StatefulWidget {
  static const double _trackHeight = 2;

  final Duration remaining;
  final double progress;

  const AppTtlTimer({
    super.key,
    required this.remaining,
    required this.progress,
  });

  @override
  State<AppTtlTimer> createState() => _AppTtlTimerState();
}

class _AppTtlTimerState extends State<AppTtlTimer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  bool get _nearZero => widget.remaining.inSeconds <= 60;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.45,
      upperBound: 1,
    );
  }

  @override
  void didUpdateWidget(AppTtlTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_nearZero && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!_nearZero && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _nearZero ? AppColors.warn : AppColors.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeTransition(
          opacity: _pulse,
          child: Text(
            'EXPIRES IN ${_formatDuration(widget.remaining)}',
            style: AppTypography.caption.copyWith(color: accent),
          ),
        ),
        const SizedBox(height: 6),
        ClipRect(
          child: SizedBox(
            height: AppTtlTimer._trackHeight,
            child: AnimatedFractionallySizedBox(
              duration: AppMotion.standard,
              curve: AppMotion.easing,
              alignment: Alignment.centerLeft,
              widthFactor: widget.progress.clamp(0, 1),
              child: Container(
                color: _nearZero ? AppColors.warn : AppColors.action,
              ),
            ),
          ),
        ),
        Container(height: 1, color: AppColors.border),
      ],
    );
  }
}
