import 'dart:io';

import 'package:application/src/features/file_transfer/file_transfer_service.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class FileTransferWidget extends StatefulWidget {
  static const double _sectionTitleFontSize = 18;
  static const double _fileNameFontSize = 15;
  static const double _metaFontSize = 12;
  static const double _progressBarHeight = 8;
  static const double _dropZoneVerticalPadding = 20;
  static const double _fileInfoBorderRadius = 8;

  final WebRTCManager webrtcManager;

  const FileTransferWidget({super.key, required this.webrtcManager});

  @override
  State<FileTransferWidget> createState() => _FileTransferWidgetState();
}

class _FileTransferWidgetState extends State<FileTransferWidget> {
  late FileTransferService _service;
  File? _selectedFile;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _service = FileTransferService(widget.webrtcManager);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final XFile? xFile = await openFile();
      if (xFile != null) {
        setState(() {
          _selectedFile = File(xFile.path);
        });
      }
    } catch (e) {
      _showError(
        'Could not open file picker: $e\n\n'
        'Troubleshooting for Linux/WSL:\n'
        '1. Ensure "zenity" is installed: sudo apt install zenity\n'
        '2. Or try dragging and dropping a file directly into the field.',
      );
    }
  }

  Future<void> _startTransfer() async {
    if (_selectedFile == null) return;
    try {
      await widget.webrtcManager.createFileTransferChannel();
      await _service.sendOffer(_selectedFile!);
      setState(() {
        _selectedFile = null; // Clear selection after starting
      });
    } catch (e) {
      _showError('Failed to send file: $e');
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File Selection Note'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FileTransferState>(
      stream: _service.onStateChange,
      initialData: _service.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;

        final variant = switch (state.status) {
          TransferStatus.completed => AppCardVariant.success,
          TransferStatus.error => AppCardVariant.error,
          TransferStatus.offered => AppCardVariant.warning,
          _ => AppCardVariant.normal,
        };

        return AppCard(
          variant: variant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.swap_horizontal_circle,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'File Transfer',
                    style: AppTypography.title(
                      size: FileTransferWidget._sectionTitleFontSize,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.base),
              _buildContent(state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(FileTransferState state) {
    if (state.status == TransferStatus.transferring ||
        state.status == TransferStatus.receiving) {
      return Column(
        children: [
          Text(
            state.status == TransferStatus.transferring
                ? 'Sending...'
                : 'Receiving...',
            style: AppTypography.body(weight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.fileName ?? 'Unknown File',
            style: AppTypography.mono(weight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: AppColors.surfaceVariant,
            color: AppColors.primary,
            minHeight: FileTransferWidget._progressBarHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${(state.progress * 100).toStringAsFixed(1)}% • ${state.bytesTransferred}/${state.totalBytes} bytes',
            style: AppTypography.mono(
              size: FileTransferWidget._metaFontSize,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => _service.cancelTransfer(reason: 'user_cancel'),
            child: Text(
              'Cancel Transfer',
              style: AppTypography.body(
                weight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      );
    }

    if (state.status == TransferStatus.offering) {
      return Column(
        children: [
          Text(
            'Waiting for peer to accept...',
            style: AppTypography.body(
              color: AppColors.textMuted,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.fileName ?? '',
            style: AppTypography.mono(weight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.base),
          const CircularProgressIndicator(color: AppColors.warning),
          const SizedBox(height: AppSpacing.base),
          TextButton(
            onPressed: () => _service.cancelTransfer(reason: 'user_cancel'),
            child: Text(
              'Cancel Request',
              style: AppTypography.body(
                color: AppColors.error,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (state.status == TransferStatus.offered) {
      return Column(
        children: [
          Text(
            'Incoming File Transfer',
            style: AppTypography.body(weight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(
                FileTransferWidget._fileInfoBorderRadius,
              ),
            ),
            child: Column(
              children: [
                Text(
                  state.fileName ?? 'unknown',
                  style: AppTypography.mono(
                    size: FileTransferWidget._fileNameFontSize,
                  ),
                ),
                Text(
                  'Size: ${(state.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                  style: AppTypography.body(
                    size: FileTransferWidget._metaFontSize,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: AppButton(
                  onPressed: () => _service.rejectOffer(),
                  label: 'Reject',
                  variant: AppButtonVariant.outline,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  onPressed: () => _service.acceptOffer(),
                  label: 'Accept',
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Default: Idle / Selected / Completed / Error
    return Column(
      children: [
        if (state.status == TransferStatus.completed) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Transfer complete!',
                style: AppTypography.body(
                  color: AppColors.success,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (state.status == TransferStatus.error) ...[
          Text(
            'Error: ${state.error}',
            style: AppTypography.body(size: 12, color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        DropTarget(
          onDragDone: (detail) {
            if (detail.files.isNotEmpty) {
              setState(() {
                _selectedFile = File(detail.files.first.path);
              });
            }
          },
          onDragEntered: (detail) => setState(() => _isDragging = true),
          onDragExited: (detail) => setState(() => _isDragging = false),
          child: GestureDetector(
            onTap: _pickFile,
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: FileTransferWidget._dropZoneVerticalPadding,
                horizontal: AppSpacing.base,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  FileTransferWidget._fileInfoBorderRadius,
                ),
                color: _isDragging
                    ? AppColors.primaryContainer
                    : AppColors.surfaceVariant,
              ),
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: _isDragging ? AppColors.primary : AppColors.outline,
                  strokeWidth: _isDragging ? 2 : 1,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        _isDragging ? Icons.file_upload : Icons.file_present,
                        color: _isDragging
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _selectedFile != null
                              ? _selectedFile!.path.split('/').last
                              : (_isDragging
                                    ? 'Drop file here'
                                    : 'Tap to select or Drag & Drop'),
                          style: _selectedFile != null || _isDragging
                              ? AppTypography.mono()
                              : AppTypography.body(
                                  color: AppColors.textMuted,
                                  weight: FontWeight.w500,
                                ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedFile != null && !_isDragging)
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            onPressed: _selectedFile == null ? null : _startTransfer,
            icon: Icons.send,
            label: 'Send File',
          ),
        ),
      ],
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _DashedBorderPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;

    void drawDashedLine(Offset start, Offset end) {
      final totalLength = (end - start).distance;
      final direction = (end - start) / totalLength;
      double drawn = 0;
      while (drawn < totalLength) {
        final currentStart = start + direction * drawn;
        final currentEnd =
            start +
            direction *
                ((drawn + dashWidth) > totalLength
                    ? totalLength
                    : (drawn + dashWidth));
        canvas.drawLine(currentStart, currentEnd, paint);
        drawn += dashWidth + dashSpace;
      }
    }

    drawDashedLine(const Offset(8, 0), Offset(size.width - 8, 0));
    drawDashedLine(Offset(size.width, 8), Offset(size.width, size.height - 8));
    drawDashedLine(Offset(size.width - 8, size.height), Offset(8, size.height));
    drawDashedLine(Offset(0, size.height - 8), const Offset(0, 8));
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
