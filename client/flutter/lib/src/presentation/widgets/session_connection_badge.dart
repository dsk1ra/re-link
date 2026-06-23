import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

enum SessionConnectionBadgeTone { connected, warning, error }

class SessionConnectionBadge extends StatelessWidget {
  const SessionConnectionBadge({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final SessionConnectionBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final dot = switch (tone) {
      SessionConnectionBadgeTone.connected => AppColors.ok,
      SessionConnectionBadgeTone.warning => AppColors.warn,
      SessionConnectionBadgeTone.error => AppColors.error,
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
