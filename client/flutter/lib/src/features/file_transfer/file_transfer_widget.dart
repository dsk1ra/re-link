import 'dart:io';

import 'package:application/src/features/file_transfer/file_transfer_service.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FileTransferWidget extends StatefulWidget {
  static const double _progressBarHeight = 2;
  static const double _dropZoneVerticalPadding = 20;

  final WebRTCManager webrtcManager;
  final FileTransferService? fileTransferService;

  const FileTransferWidget({
    super.key,
    required this.webrtcManager,
    this.fileTransferService,
  });

  @override
  State<FileTransferWidget> createState() => _FileTransferWidgetState();
}

class _FileTransferWidgetState extends State<FileTransferWidget> {
  late FileTransferService _service;
  late bool _ownsService;
  List<File> _selectedFiles = [];
  int _batchTotal = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fileTransferService == null;
    _service =
        widget.fileTransferService ?? FileTransferService(widget.webrtcManager);
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final files = await openFiles();
      if (files.isNotEmpty) {
        setState(() {
          _selectedFiles = files.map((f) => File(f.path)).toList();
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
    if (_selectedFiles.isEmpty) return;
    try {
      await widget.webrtcManager.createFileTransferChannel();
      _batchTotal = _selectedFiles.length;
      await _service.sendOffers(_selectedFiles);
      setState(() {
        _selectedFiles = []; // Clear selection after starting
      });
    } catch (e) {
      _showError('Failed to send file: $e');
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FILE TRANSFER', style: AppTypography.eyebrow),
            const SizedBox(height: AppSpacing.sm),
            Text('File selection note', style: AppTypography.h2),
          ],
        ),
        content: Text(
          message,
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(String text, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(text, style: AppTypography.caption.copyWith(color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FileTransferState>(
      stream: _service.onStateChange,
      initialData: _service.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;

        return AppCard(child: _buildContent(state));
      },
    );
  }

  Widget _buildContent(FileTransferState state) {
    if (state.status == TransferStatus.transferring ||
        state.status == TransferStatus.receiving) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusLine(
            state.status == TransferStatus.transferring
                ? 'SENDING'
                : 'RECEIVING',
            AppColors.warn,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            state.fileName ?? 'Unknown File',
            textAlign: TextAlign.center,
            style: AppTypography.data,
          ),
          if (state.status == TransferStatus.transferring && _batchTotal > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'File ${_batchTotal - _service.queuedCount} of $_batchTotal',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: state.progress,
            minHeight: FileTransferWidget._progressBarHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${(state.progress * 100).toStringAsFixed(1)}% · '
            '${state.bytesTransferred}/${state.totalBytes} bytes',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => _service.cancelTransfer(reason: 'user_cancel'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('CANCEL TRANSFER'),
          ),
        ],
      );
    }

    if (state.status == TransferStatus.offering) {
      return Column(
        children: [
          _statusLine('WAITING FOR PEER TO ACCEPT', AppColors.warn),
          const SizedBox(height: AppSpacing.md),
          Text(state.fileName ?? '', style: AppTypography.data),
          const SizedBox(height: AppSpacing.md),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.warn),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => _service.cancelTransfer(reason: 'user_cancel'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('CANCEL REQUEST'),
          ),
        ],
      );
    }

    if (state.status == TransferStatus.offered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('INCOMING FILE', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.fileName ?? 'unknown', style: AppTypography.data),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${(state.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _service.rejectOffer(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('REJECT'),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.status == TransferStatus.completed) ...[
          _statusLine('TRANSFER COMPLETE', AppColors.ok),
          const SizedBox(height: AppSpacing.md),
        ],
        if (state.status == TransferStatus.error) ...[
          _statusLine('TRANSFER FAILED', AppColors.error),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${state.error}',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        DropTarget(
          onDragDone: (detail) {
            if (detail.files.isNotEmpty) {
              setState(() {
                _selectedFiles = detail.files.map((f) => File(f.path)).toList();
              });
            }
          },
          onDragEntered: (detail) => setState(() => _isDragging = true),
          onDragExited: (detail) => setState(() => _isDragging = false),
          child: GestureDetector(
            onTap: _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: FileTransferWidget._dropZoneVerticalPadding,
                horizontal: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: _isDragging ? AppColors.surface2 : AppColors.background,
              ),
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: _isDragging
                      ? AppColors.borderStrong
                      : AppColors.border,
                  strokeWidth: 1,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        _isDragging ? LucideIcons.fileUp : LucideIcons.file,
                        size: 18,
                        color: _isDragging
                            ? AppColors.action
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _selectedFiles.isNotEmpty
                              ? (_selectedFiles.length == 1
                                    ? _selectedFiles.first.path
                                          .split('/')
                                          .last
                                    : '${_selectedFiles.length} files selected')
                              : (_isDragging
                                    ? 'Drop files here'
                                    : 'Tap to select or drag & drop'),
                          style: _selectedFiles.isNotEmpty || _isDragging
                              ? AppTypography.data
                              : AppTypography.label.copyWith(
                                  color: AppColors.textMuted,
                                ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedFiles.isNotEmpty && !_isDragging)
                        const Icon(
                          LucideIcons.check,
                          size: 18,
                          color: AppColors.ok,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            onPressed: _selectedFiles.isEmpty ? null : _startTransfer,
            icon: LucideIcons.send,
            label: _selectedFiles.length > 1
                ? 'Send ${_selectedFiles.length} files'
                : 'Send file',
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
