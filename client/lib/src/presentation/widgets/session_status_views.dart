import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
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
          variant: AppCardVariant.error,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cancel,
                size: AppUiMetrics.disconnectedIconSize,
                color: AppColors.error,
              ),
              const SizedBox(height: AppSpacing.base),
              Text('Connection Ended', style: AppTypography.title()),
              const SizedBox(height: AppSpacing.base),
              ElevatedButton(
                onPressed: onReturnHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: const Text('Return to Home'),
              ),
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
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          Text(message),
        ],
      ),
    );
  }
}
