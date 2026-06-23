import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

enum StatusBadgeTone { neutral, success, warning, error }

/// 2px-radius mono chip with a status dot. The semantic colour lives in the
/// dot only; the chip itself stays neutral.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusBadgeTone tone;

  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusBadgeTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final Color dot = switch (tone) {
      StatusBadgeTone.neutral => AppColors.textMuted,
      StatusBadgeTone.success => AppColors.ok,
      StatusBadgeTone.warning => AppColors.warn,
      StatusBadgeTone.error => AppColors.error,
    };

    return Container(
      padding: AppUiMetrics.badgePadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppUiMetrics.badgeBorderRadius),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppUiMetrics.badgeDotSize,
            height: AppUiMetrics.badgeDotSize,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppUiMetrics.badgeDotGap),
          Text(label.toUpperCase(), style: AppTypography.caption),
        ],
      ),
    );
  }
}
