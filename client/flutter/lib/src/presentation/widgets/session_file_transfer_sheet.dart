import 'package:flutter/material.dart';

import 'package:application/src/features/file_transfer/file_transfer_widget.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

Future<void> showSessionFileTransferSheet({
  required BuildContext context,
  required WebRTCManager webrtcManager,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) =>
        _SessionFileTransferSheetFrame(webrtcManager: webrtcManager),
  );
}

class _SessionFileTransferSheetFrame extends StatelessWidget {
  const _SessionFileTransferSheetFrame({this.webrtcManager});

  final WebRTCManager? webrtcManager;

  static const double _dragHandleWidth = 40;
  static const double _dragHandleHeight = 4;
  static const double _dragHandleBorderRadius = 2;
  static const double _sheetHeaderIconSize = 18;
  static const double _sheetHeaderIconGap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final manager = webrtcManager;
    if (manager == null) {
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
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(
                      _dragHandleBorderRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(
                    Icons.swap_horiz,
                    color: AppColors.textMuted,
                    size: _sheetHeaderIconSize,
                  ),
                  const SizedBox(width: _sheetHeaderIconGap),
                  Text(
                    'File Transfer',
                    style: AppTypography.body(weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FileTransferWidget(webrtcManager: manager),
            ],
          ),
        ),
      ),
    );
  }
}
