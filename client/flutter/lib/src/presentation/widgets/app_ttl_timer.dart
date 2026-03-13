import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/ui/typography.dart';

class AppTtlTimer extends StatelessWidget {
  static const double _timerSize = 74;
  static const double _trackStrokeWidth = 4;
  static const double _timeFontSize = 11;

  final Duration remaining;
  final double progress;

  const AppTtlTimer({
    super.key,
    required this.remaining,
    required this.progress,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _timerSize,
      height: _timerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: _trackStrokeWidth,
            backgroundColor: AppColors.surfaceVariant,
            color: AppColors.primary,
          ),
          Text(
            _formatDuration(remaining),
            style: AppTypography.mono(size: _timeFontSize, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
