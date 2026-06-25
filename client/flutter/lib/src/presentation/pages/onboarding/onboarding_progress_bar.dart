import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

class OnboardingProgressBar extends StatelessWidget {
  final int currentPage;
  final Set<int> completedPages;
  final int totalPages;

  const OnboardingProgressBar({
    super.key,
    required this.currentPage,
    required this.completedPages,
    this.totalPages = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(totalPages, (index) {
              final isCompleted = completedPages.contains(index);
              final isCurrent = index == currentPage;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index < totalPages - 1 ? AppSpacing.xs : 0,
                  ),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppColors.action
                          : isCurrent
                              ? AppColors.action.withValues(alpha: 0.4)
                              : AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${currentPage + 1} / $totalPages',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}
