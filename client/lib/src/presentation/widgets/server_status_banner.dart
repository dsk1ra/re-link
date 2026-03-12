import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';

class ServerStatusBanner extends StatelessWidget {
  static const double _stripeWidth = 6;
  static const double _stripeHeight = 28;
  static const double _spinnerSize = 18;
  static const double _maxContentWidth = 900;

  final bool connecting;
  final bool connected;
  final String connectedText;
  final VoidCallback onRetry;

  const ServerStatusBanner({
    super.key,
    required this.connecting,
    required this.connected,
    required this.connectedText,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Color stripeColor = connected
        ? AppColors.success
        : (connecting ? AppColors.warning : AppColors.error);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Row(
            children: [
              Container(width: _stripeWidth, height: _stripeHeight, color: stripeColor),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: connecting
                    ? Row(
                        children: [
                          const SizedBox(
                            width: _spinnerSize,
                            height: _spinnerSize,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text('Connecting to server...', style: AppTypography.body()),
                        ],
                      )
                    : Text(
                        connected ? connectedText : 'Not connected',
                        style: AppTypography.body(),
                      ),
              ),
              if (!connecting && !connected)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    'Retry',
                    style: AppTypography.body(
                      weight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
