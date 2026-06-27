import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/rust/api/audio.dart' as rust_audio;

enum VoiceDialogAction { start, apply, stop }

class VoiceDialogResult {
  const VoiceDialogResult({required this.action, this.sourceId});

  final VoiceDialogAction action;
  final String? sourceId;
}

/// Microphone selection dialog shared by the initiator and responder session
/// menus. When voice is not yet active it offers to start it; when active it
/// allows switching the input device or stopping voice entirely.
Future<VoiceDialogResult?> showSessionVoiceDialog({
  required BuildContext context,
  required List<rust_audio.AudioSourceDto> sources,
  required String? selectedSourceId,
  required bool audioActive,
}) {
  const dialogWidth = 400.0;
  const dropdownItemWidth = 320.0;

  String? dialogSourceId =
      sources.any((source) => source.id == selectedSourceId)
      ? selectedSourceId
      : (sources.isNotEmpty ? sources.first.id : null);

  return showDialog<VoiceDialogResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VOICE CHAT', style: AppTypography.eyebrow),
            const SizedBox(height: AppSpacing.sm),
            Text('Share microphone', style: AppTypography.h2),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sources.isEmpty)
                Text(
                  'No microphones available.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textMuted,
                  ),
                )
              else ...[
                Text('MICROPHONE', style: AppTypography.eyebrow),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: dialogSourceId,
                  dropdownColor: AppColors.surface2,
                  style: AppTypography.label,
                  items: sources
                      .map(
                        (source) => DropdownMenuItem<String>(
                          value: source.id,
                          child: SizedBox(
                            width: dropdownItemWidth,
                            child: Text(
                              source.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.label,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => dialogSourceId = val),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Voice is sent directly to your peer over the encrypted '
                  'session. Mute any time from the session menu.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (audioActive)
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(
                const VoiceDialogResult(action: VoiceDialogAction.stop),
              ),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('STOP VOICE'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('CANCEL'),
          ),
          AppButton(
            onPressed: dialogSourceId == null
                ? null
                : () => Navigator.of(ctx).pop(
                    VoiceDialogResult(
                      action: audioActive
                          ? VoiceDialogAction.apply
                          : VoiceDialogAction.start,
                      sourceId: dialogSourceId,
                    ),
                  ),
            icon: LucideIcons.mic,
            label: audioActive ? 'Apply' : 'Start voice',
          ),
        ],
      ),
    ),
  );
}
