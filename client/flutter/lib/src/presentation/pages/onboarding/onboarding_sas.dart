import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

class OnboardingSas extends StatelessWidget {
  final VoidCallback onUnderstood;

  const OnboardingSas({super.key, required this.onUnderstood});

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
              const SizedBox(height: AppSpacing.xl),
              Text('VERIFICATION', style: AppTypography.eyebrow),
              const SizedBox(height: AppSpacing.md),
              const Text('Verify every session', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Every session generates a 9-digit code derived '
                'deterministically from the shared secret. Both devices show '
                'the same code. Both users must read it and confirm it '
                'matches before the session opens.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                emphasized: true,
                child: Column(
                  children: [
                    Text('VERIFY WITH PEER', style: AppTypography.eyebrow),
                    const SizedBox(height: AppSpacing.lg),
                    const Text('247 918 653', style: AppTypography.displayData),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Same code appears on both devices',
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
                  color: AppColors.error.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: AppUiMetrics.iconSize,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'If the codes do not match, the connection may be '
                        'intercepted. Close the session immediately and '
                        'establish contact via a different channel.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _VerificationRule(
                icon: LucideIcons.mic,
                text: 'Read the code aloud over a voice call.',
              ),
              const _VerificationRule(
                icon: LucideIcons.users,
                text: 'Confirm it in person if possible.',
              ),
              const _VerificationRule(
                icon: LucideIcons.unlink,
                text: 'Never verify via the same channel used to share the '
                    'invite link. If an attacker intercepted the link, they '
                    'can intercept that channel too.',
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: onUnderstood,
                  label: 'Understood — finish setup',
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

class _VerificationRule extends StatelessWidget {
  final IconData icon;
  final String text;

  const _VerificationRule({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppUiMetrics.iconSize, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
