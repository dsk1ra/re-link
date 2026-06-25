import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

class OnboardingReady extends StatelessWidget {
  final String serverAddress;
  final bool? serverReachable;
  final bool healthCheckLoading;
  final bool useDefaultIce;
  final VoidCallback onOpenReLink;

  const OnboardingReady({
    super.key,
    required this.serverAddress,
    required this.serverReachable,
    required this.healthCheckLoading,
    required this.useDefaultIce,
    required this.onOpenReLink,
  });

  String get _displayServer {
    var display = serverAddress;
    if (display.startsWith('https://')) {
      display = display.substring(8);
    } else if (display.startsWith('http://')) {
      display = display.substring(7);
    }
    return display;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppUiMetrics.formWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Icon(
                  LucideIcons.circleCheck,
                  size: 48,
                  color: AppColors.ok,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Center(
                child: Text('You\'re ready.', style: AppTypography.h1),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                eyebrow: 'Configuration summary',
                child: Column(
                  children: [
                    _SummaryRow(
                      label: 'Relay server',
                      value: _displayServer,
                      ok: serverAddress.isNotEmpty,
                    ),
                    const Divider(height: AppSpacing.md),
                    _SummaryRow(
                      label: 'Server health',
                      value: healthCheckLoading
                          ? 'checking...'
                          : (serverReachable == true
                              ? 'reachable'
                              : 'unreachable'),
                      ok: serverReachable == true,
                      loading: healthCheckLoading,
                    ),
                    const Divider(height: AppSpacing.md),
                    _SummaryRow(
                      label: 'ICE servers',
                      value: useDefaultIce ? 'auto (from relay)' : 'custom',
                      ok: true,
                    ),
                    const Divider(height: AppSpacing.md),
                    const _SummaryRow(
                      label: 'SAS verification',
                      value: 'required',
                      ok: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                eyebrow: 'First connection',
                child: Text(
                  'Tap Create link on the main screen, share the link with '
                  'your peer via any channel, and verify the SAS code '
                  'together before the session opens.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: onOpenReLink,
                  label: 'Open Re:Link',
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;
  final bool loading;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.ok,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.label.copyWith(color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: AppTypography.data.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (loading)
                  const SizedBox(
                    width: 12,
                    height: 12,
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
                      color: ok ? AppColors.ok : AppColors.warn,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
