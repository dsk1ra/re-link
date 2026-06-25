import 'package:flutter/material.dart';

import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

class OnboardingIceConfig extends StatelessWidget {
  final bool useDefaultIce;
  final ValueChanged<bool> onToggleDefaultIce;
  final TextEditingController stunController;
  final TextEditingController turnController;
  final TextEditingController turnUsernameController;
  final TextEditingController turnCredentialController;
  final VoidCallback onNext;

  const OnboardingIceConfig({
    super.key,
    required this.useDefaultIce,
    required this.onToggleDefaultIce,
    required this.stunController,
    required this.turnController,
    required this.turnUsernameController,
    required this.turnCredentialController,
    required this.onNext,
  });

  bool get _canProceed {
    if (useDefaultIce) return true;
    final turn = turnController.text.trim();
    if (turn.isEmpty) return true;
    return turnUsernameController.text.trim().isNotEmpty &&
        turnCredentialController.text.trim().isNotEmpty;
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
              const SizedBox(height: AppSpacing.xl),
              Text(
                'STEP 2 OF 2',
                style: AppTypography.eyebrow.copyWith(color: AppColors.action),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('NAT traversal', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.md),
              Text(
                'STUN tells each device its public address so a direct '
                'connection can be attempted. TURN relays traffic when no '
                'direct path is possible — it is used only as a fallback.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                eyebrow: 'ICE configuration',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      value: useDefaultIce,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Use server-derived ICE defaults',
                        style: AppTypography.label,
                      ),
                      subtitle: Text(
                        'STUN and TURN configuration pulled from the relay '
                        'server automatically.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textFaint,
                        ),
                      ),
                      onChanged: onToggleDefaultIce,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _fieldLabel('Custom STUN server'),
                    TextField(
                      controller: stunController,
                      enabled: !useDefaultIce,
                      style: AppTypography.data,
                      decoration: const InputDecoration(
                        hintText: 'stun:stun.example.org:3478',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _fieldLabel('Custom TURN server'),
                    TextField(
                      controller: turnController,
                      enabled: !useDefaultIce,
                      style: AppTypography.data,
                      decoration: const InputDecoration(
                        hintText: 'turn:turn.example.org:3478',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Username'),
                              TextField(
                                controller: turnUsernameController,
                                enabled: !useDefaultIce,
                                style: AppTypography.data,
                                decoration: const InputDecoration(
                                  hintText: 'username',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Credential'),
                              TextField(
                                controller: turnCredentialController,
                                enabled: !useDefaultIce,
                                obscureText: true,
                                style: AppTypography.data,
                                decoration: const InputDecoration(
                                  hintText: 'credential',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!useDefaultIce &&
                        turnController.text.trim().isNotEmpty &&
                        (turnUsernameController.text.trim().isEmpty ||
                            turnCredentialController.text.trim().isEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          'TURN credentials required — add a username and password.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warn,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Custom ICE servers are for advanced deployments. Most users '
                'should leave the toggle on.',
                style:
                    AppTypography.caption.copyWith(color: AppColors.textFaint),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed: _canProceed ? onNext : null,
                  label: 'Next: learn about verification',
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text.toUpperCase(), style: AppTypography.eyebrow),
    );
  }
}
