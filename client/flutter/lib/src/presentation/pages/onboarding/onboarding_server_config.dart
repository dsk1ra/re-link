import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

class OnboardingServerConfig extends StatefulWidget {
  final TextEditingController serverAddressController;
  final bool? serverReachable;
  final bool healthCheckLoading;
  final VoidCallback onCheckHealth;
  final VoidCallback onNext;

  const OnboardingServerConfig({
    super.key,
    required this.serverAddressController,
    required this.serverReachable,
    required this.healthCheckLoading,
    required this.onCheckHealth,
    required this.onNext,
  });

  @override
  State<OnboardingServerConfig> createState() => _OnboardingServerConfigState();
}

class _OnboardingServerConfigState extends State<OnboardingServerConfig> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus &&
        widget.serverAddressController.text.trim().isNotEmpty) {
      widget.onCheckHealth();
    }
  }

  Widget? _buildSuffix() {
    if (widget.healthCheckLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.warn),
        ),
      );
    }

    if (widget.serverReachable == null) return null;

    final color = widget.serverReachable! ? AppColors.ok : AppColors.warn;
    final label = widget.serverReachable! ? 'reachable' : 'unreachable';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppUiMetrics.badgeDotSize,
          height: AppUiMetrics.badgeDotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.caption.copyWith(color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canProceed =
        widget.serverReachable == true && !widget.healthCheckLoading;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppUiMetrics.formWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                'STEP 1 OF 2',
                style: AppTypography.eyebrow.copyWith(color: AppColors.action),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Server address', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Point Re:Link at your relay server. The server brokers the '
                'rendezvous and sees nothing else.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                eyebrow: 'Server address',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: widget.serverAddressController,
                      focusNode: _focusNode,
                      style: AppTypography.data,
                      decoration: InputDecoration(
                        hintText: 'https://relay.example.org',
                        suffixIcon: _buildSuffix() != null
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.sm,
                                ),
                                child: _buildSuffix(),
                              )
                            : null,
                        suffixIconConstraints: const BoxConstraints(
                          minHeight: 0,
                          minWidth: 0,
                        ),
                      ),
                      onSubmitted: (_) => widget.onCheckHealth(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (widget.serverReachable == false &&
                        !widget.healthCheckLoading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          'Can\'t reach this server. Check the address and '
                          'confirm the server is running.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warn,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                eyebrow: 'Self-hosting',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Don\'t have a server running yet? The minimum deployment:',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadius.none),
                      ),
                      child: SelectableText(
                        'docker compose up -d',
                        style: AppTypography.data.copyWith(
                          color: AppColors.action,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'See the self-hosting documentation for full setup.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.warn.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: AppUiMetrics.iconSize,
                      color: AppColors.warn,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Using a third-party relay is inadvisable for '
                        'high-stakes connections. Even a relay that cannot '
                        'read session content can observe connection metadata '
                        'and client IP addresses.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warn,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: canProceed ? widget.onNext : null,
                  label: 'Next: NAT traversal',
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
