import 'package:flutter/material.dart';

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
    this.handleIconSize = 45,
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
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: AnimatedSlide(
                  offset: isOpen ? Offset.zero : const Offset(0, -1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  child: child,
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            top: isOpen ? openTop : closedTop,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedRotation(
                  turns: isOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.expand_more,
                    size: handleIconSize,
                    color: AppColors.primary,
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
    required this.cornerRadius,
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
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(color: AppColors.outline),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double iconSize;
  final double labelFontSize;
  final Color? color;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final actionColor = onPressed == null
        ? AppColors.textMuted.withValues(alpha: 0.6)
        : (color ?? AppColors.textPrimary);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
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
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: actionColor, size: iconSize),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.body(
                size: labelFontSize,
                color: actionColor,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
