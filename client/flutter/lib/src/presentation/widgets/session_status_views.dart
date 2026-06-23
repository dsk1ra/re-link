import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

class SessionDisconnectedView extends StatelessWidget {
  const SessionDisconnectedView({super.key, required this.onReturnHome});

  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: AppCard(
          emphasized: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'SESSION TERMINATED',
                    style: AppTypography.eyebrow.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Connection ended', style: AppTypography.h2),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The encrypted channel is closed. Session keys are gone.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(onPressed: onReturnHome, label: 'Return to home'),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionConnectingView extends StatelessWidget {
  const SessionConnectingView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.warn),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            message.toUpperCase(),
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
