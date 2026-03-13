import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/ui/typography.dart';

enum StatusBadgeTone { neutral, success, warning, error }

class StatusBadge extends StatelessWidget {
  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 10, vertical: 6);
  static const double _labelFontSize = 12;

  final String label;
  final StatusBadgeTone tone;

  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusBadgeTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = switch (tone) {
      StatusBadgeTone.neutral => AppColors.primary,
      StatusBadgeTone.success => AppColors.success,
      StatusBadgeTone.warning => AppColors.warning,
      StatusBadgeTone.error => AppColors.error,
    };

    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: accent),
      ),
      child: Text(
        label,
        style: AppTypography.body(size: _labelFontSize, weight: FontWeight.w600),
      ),
    );
  }
}
