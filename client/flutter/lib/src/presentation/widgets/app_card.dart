import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

enum AppCardVariant { normal, success, warning, error }

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final AppCardVariant variant;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.variant = AppCardVariant.normal,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = switch (variant) {
      AppCardVariant.normal => AppColors.outline,
      AppCardVariant.success => AppColors.success,
      AppCardVariant.warning => AppColors.warning,
      AppCardVariant.error => AppColors.error,
    };

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.base),
        child: child,
      ),
    );
  }
}
