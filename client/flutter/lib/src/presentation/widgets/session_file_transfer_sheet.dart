import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:application/src/features/file_transfer/file_transfer_service.dart';
import 'package:application/src/features/file_transfer/file_transfer_widget.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

Future<void> showSessionFileTransferSheet({
  required BuildContext context,
  required WebRTCManager webrtcManager,
  required FileTransferService fileTransferService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface2,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      side: BorderSide(color: AppColors.borderStrong),
    ),
    builder: (ctx) => _SessionFileTransferSheetFrame(
      webrtcManager: webrtcManager,
      fileTransferService: fileTransferService,
    ),
  );
}

class _SessionFileTransferSheetFrame extends StatelessWidget {
  const _SessionFileTransferSheetFrame({
    this.webrtcManager,
    this.fileTransferService,
  });

  final WebRTCManager? webrtcManager;
  final FileTransferService? fileTransferService;

  static const double _dragHandleWidth = 32;
  static const double _dragHandleHeight = 3;
  static const double _sheetHeaderIconSize = 16;
  static const double _sheetHeaderIconGap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final manager = webrtcManager;
    final transferService = fileTransferService;
    if (manager == null || transferService == null) {
      return const SizedBox.shrink();
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      builder: (ctx, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: _dragHandleWidth,
                  height: _dragHandleHeight,
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  color: AppColors.borderStrong,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(
                    LucideIcons.arrowLeftRight,
                    color: AppColors.textMuted,
                    size: _sheetHeaderIconSize,
                  ),
                  const SizedBox(width: _sheetHeaderIconGap),
                  Text('FILE TRANSFER', style: AppTypography.eyebrow),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FileTransferWidget(
                webrtcManager: manager,
                fileTransferService: transferService,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
