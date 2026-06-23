import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// Full-width hairline-bordered strip with a status dot.
/// Status lives in the dot and the text — never in a coloured fill.
class ServerStatusBanner extends StatelessWidget {
  static const double _spinnerSize = 12;

  final bool connecting;
  final bool connected;
  final String connectedText;
  final String? errorDetail;
  final VoidCallback onRetry;

  const ServerStatusBanner({
    super.key,
    required this.connecting,
    required this.connected,
    required this.connectedText,
    this.errorDetail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = connected
        ? AppColors.ok
        : (connecting ? AppColors.warn : AppColors.error);
    final String statusText = connecting
        ? 'CONNECTING TO SERVER'
        : (connected ? connectedText.toUpperCase() : 'NOT CONNECTED');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppUiMetrics.maxContentWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (connecting)
                    const SizedBox(
                      width: _spinnerSize,
                      height: _spinnerSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.warn),
                      ),
                    )
                  else
                    Container(
                      width: AppUiMetrics.badgeDotSize,
                      height: AppUiMetrics.badgeDotSize,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                  Expanded(
                    child: Text(
                      statusText,
                      style: AppTypography.caption.copyWith(color: dotColor),
                    ),
                  ),
                  if (!connecting && !connected)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('RETRY'),
                    ),
                ],
              ),
              if (!connecting && !connected && errorDetail != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppUiMetrics.badgeDotSize +
                        AppSpacing.sm +
                        AppSpacing.xs,
                    top: 2,
                  ),
                  child: Text(
                    errorDetail!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
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
