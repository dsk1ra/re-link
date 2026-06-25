import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';

class OnboardingWelcome extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSkipToSetup;

  const OnboardingWelcome({
    super.key,
    required this.onGetStarted,
    required this.onSkipToSetup,
  });

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
              Text(
                'RE:LINK',
                style: AppTypography.eyebrow.copyWith(
                  color: AppColors.action,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Welcome', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Server-blind, ephemeral peer-to-peer remote access.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _TrustFact(
                icon: LucideIcons.userX,
                title: 'No accounts',
                description:
                    'No sign-ups, no credentials, no identity tied to sessions.',
              ),
              const _TrustFact(
                icon: LucideIcons.cloudOff,
                title: 'No cloud storage',
                description:
                    'Files and streams transfer directly between devices. '
                    'Nothing is stored on the relay.',
              ),
              const _TrustFact(
                icon: LucideIcons.eyeOff,
                title: 'No persistent records',
                description:
                    'The relay server coordinates connections but never reads '
                    'data. It sees encrypted payloads and forgets them.',
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: onGetStarted,
                  label: 'Get started',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: onSkipToSetup,
                  child: Text(
                    'I know what I’m doing — skip to setup',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textFaint,
                    ),
                  ),
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

class _TrustFact extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _TrustFact({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppUiMetrics.iconSize, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style:
                      AppTypography.body.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
