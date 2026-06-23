import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// Bordered flat panel. Depth comes from the border and the surface
/// luminance step, never shadows. Status colours never appear on borders;
/// state is communicated with dots and status text inside the card.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Optional uppercase mono label rendered above the content.
  final String? eyebrow;

  /// Set for emphasised panels (e.g. the active region of a screen).
  final bool emphasized;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.eyebrow,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: emphasized ? AppColors.borderStrong : AppColors.border,
        ),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        child: eyebrow == null
            ? child
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow!.toUpperCase(), style: AppTypography.eyebrow),
                  const SizedBox(height: AppSpacing.md),
                  child,
                ],
              ),
      ),
    );
  }
}
