import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/ui/typography.dart';

enum AppButtonVariant { primary, outline }

class AppButton extends StatelessWidget {
  static const double _iconSize = 18;
  static const double _spinnerSize = 16;
  static const double _iconGap = AppSpacing.sm;
  static const EdgeInsets _buttonPadding =
      EdgeInsets.symmetric(vertical: 14, horizontal: 14);
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;
  final AppButtonVariant variant;

  const AppButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(
            width: _spinnerSize,
            height: _spinnerSize,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: _iconSize),
        if (loading || icon != null) const SizedBox(width: _iconGap),
        Text(label, style: AppTypography.body(weight: FontWeight.w600)),
      ],
    );

    if (variant == AppButtonVariant.outline) {
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.outline),
          padding: _buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: content,
      );
    }

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.surfaceVariant,
        disabledForegroundColor: AppColors.textMuted,
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: content,
    );
  }
}
