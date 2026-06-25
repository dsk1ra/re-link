import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

class OnboardingHowItWorks extends StatelessWidget {
  final VoidCallback onNext;

  const OnboardingHowItWorks({super.key, required this.onNext});

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
              Text('HOW IT WORKS', style: AppTypography.eyebrow),
              const SizedBox(height: AppSpacing.md),
              const Text('The blind relay model', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.lg),
              const _RelayDiagram(),
              const SizedBox(height: AppSpacing.lg),
              const _ExplanationPoint(
                number: '1',
                text: 'The relay matches two devices and then plays no further '
                    'role. A seized or compromised relay cannot reconstruct '
                    'session content because it never held it.',
              ),
              const _ExplanationPoint(
                number: '2',
                text: 'Keys are derived locally from a secret embedded in the '
                    'invite link. The relay never receives this secret; it '
                    'only ever sees encrypted payloads.',
              ),
              const _ExplanationPoint(
                number: '3',
                text: 'Each session uses a one-time token. Nothing links one '
                    'session to another, even from the same two devices.',
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              const _FeatureItem(
                icon: LucideIcons.keyRound,
                text: 'Key derivation stays on device',
              ),
              const _FeatureItem(
                icon: LucideIcons.shieldCheck,
                text: 'SAS verification defeats man-in-the-middle attacks',
              ),
              const _FeatureItem(
                icon: LucideIcons.timer,
                text: 'Sessions are disposable by design',
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: onNext,
                  label: 'Next: set up your server',
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

class _RelayDiagram extends StatelessWidget {
  const _RelayDiagram();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Text('DURING PAIRING', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(child: _DiagramNode(icon: LucideIcons.monitor, label: 'YOU')),
              _connector(AppColors.borderStrong),
              const Expanded(child: _DiagramNode(icon: LucideIcons.server, label: 'RELAY')),
              _connector(AppColors.borderStrong),
              const Expanded(child: _DiagramNode(icon: LucideIcons.monitor, label: 'PEER')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('AFTER CONNECTION', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(child: _DiagramNode(icon: LucideIcons.monitor, label: 'YOU')),
              Expanded(
                child: Column(
                  children: [
                    Container(height: 1, color: AppColors.action),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'DIRECT P2P',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.action,
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(child: _DiagramNode(icon: LucideIcons.monitor, label: 'PEER')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Relay steps out — sees nothing',
            style: AppTypography.caption.copyWith(color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  static Widget _connector(Color color) {
    return Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        color: color,
      ),
    );
  }
}

class _DiagramNode extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DiagramNode({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: AppUiMetrics.iconSize, color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}

class _ExplanationPoint extends StatelessWidget {
  final String number;
  final String text;

  const _ExplanationPoint({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              number,
              style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
            ),
          ),
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

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: AppUiMetrics.iconSize, color: AppColors.action),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text, style: AppTypography.label),
          ),
        ],
      ),
    );
  }
}
