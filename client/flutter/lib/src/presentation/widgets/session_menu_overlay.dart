import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/motion.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

class SessionMenuOverlay extends StatelessWidget {
  const SessionMenuOverlay({
    super.key,
    required this.width,
    required this.height,
    required this.isOpen,
    required this.onToggle,
    required this.child,
    this.handleIconSize = 36,
    this.closedTop = 0,
    this.openTop = 108,
  });

  final double width;
  final double height;
  final bool isOpen;
  final VoidCallback onToggle;
  final Widget child;
  final double handleIconSize;
  final double closedTop;
  final double openTop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !isOpen,
              child: AnimatedOpacity(
                opacity: isOpen ? 1 : 0,
                duration: AppMotion.standard,
                curve: AppMotion.easing,
                child: AnimatedSlide(
                  offset: isOpen ? Offset.zero : const Offset(0, -1.0),
                  duration: AppMotion.large,
                  curve: AppMotion.easing,
                  child: child,
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: AppMotion.large,
            curve: AppMotion.easing,
            top: isOpen ? openTop : closedTop,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedRotation(
                  turns: isOpen ? 0.5 : 0.0,
                  duration: AppMotion.standard,
                  curve: AppMotion.easing,
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: handleIconSize,
                    color: AppColors.action,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SessionMenuCard extends StatelessWidget {
  const SessionMenuCard({
    super.key,
    required this.width,
    this.cornerRadius = AppRadius.md,
    required this.child,
  });

  final double width;
  final double cornerRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: child,
    );
  }
}

class SessionMenuAction extends StatelessWidget {
  const SessionMenuAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.iconSize,
    required this.labelFontSize,
    this.color,
    this.showSpinner = false,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double iconSize;
  final double labelFontSize;
  final Color? color;
  final bool showSpinner;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final actionColor = onPressed == null
        ? AppColors.textFaint
        : (color ?? AppColors.textPrimary);

    return InkWell(
      onTap: onPressed,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: const CircularProgressIndicator(strokeWidth: 1.5),
              )
            else
              Icon(icon, color: actionColor, size: iconSize),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                fontSize: labelFontSize,
                color: actionColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
