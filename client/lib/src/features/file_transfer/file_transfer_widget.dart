import 'dart:io';

import 'package:application/src/features/file_transfer/file_transfer_service.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class FileTransferWidget extends StatefulWidget {
  final WebRTCManager webrtcManager;

  const FileTransferWidget({
    super.key,
    required this.webrtcManager,
  });

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
        
        return Card(
          color: const Color(0xFFffffff),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.swap_horizontal_circle, color: Color(0xFFcc3f0c)),
                    SizedBox(width: 8),
                    Text(
                      'File Transfer',
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF19231a),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildContent(state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(FileTransferState state) {
    if (state.status == TransferStatus.transferring || state.status == TransferStatus.receiving) {
       return Column(
          children: [
            Text(state.status == TransferStatus.transferring ? 'Sending...' : 'Receiving...'),
            const SizedBox(height: 8),
            Text(state.fileName ?? 'Unknown File', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.progress,
              backgroundColor: const Color(0xFFd8cbc7),
              color: const Color(0xFFcc3f0c),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text('${(state.progress * 100).toStringAsFixed(1)}%'),
          ],
        );
    }

    if (state.status == TransferStatus.offering) {
        return Column(
          children: [
            const Text('Waiting for peer to accept...', style: TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Text(state.fileName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: Color(0xFFcc3f0c)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _service.rejectOffer(),
              child: const Text('Cancel Request', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
    }

    if (state.status == TransferStatus.offered) {
        return Column(
          children: [
            const Text('Incoming File Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFd8cbc7).withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(state.fileName ?? 'unknown', style: const TextStyle(fontSize: 16)),
                  Text('Size: ${(state.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB', 
                       style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () => _service.rejectOffer(),
                  child: const Text('Reject'),
                ),
                ElevatedButton(
                  onPressed: () => _service.acceptOffer(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFcc3f0c),
                    foregroundColor: const Color(0xFFffffff),
                  ),
                  child: const Text('Accept & Download'),
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
           const Row(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Icon(Icons.check_circle, color: Colors.green, size: 16),
               SizedBox(width: 4),
               Text('Transfer complete!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
             ],
           ),
           const SizedBox(height: 12),
        ],
        if (state.status == TransferStatus.error) ...[
           Text('Error: ${state.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
           const SizedBox(height: 12),
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
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isDragging ? const Color(0xFFcc3f0c) : const Color(0xFF19231a), 
                  width: _isDragging ? 2 : 1,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(8),
                color: _isDragging ? const Color(0xFFcc3f0c).withOpacity(0.05) : const Color(0xFFf5f5f5),
              ),
              child: Row(
                children: [
                  Icon(
                    _isDragging ? Icons.file_upload : Icons.file_present, 
                    color: _isDragging ? const Color(0xFFcc3f0c) : const Color(0xFF19231a)
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFile != null 
                          ? _selectedFile!.path.split('/').last 
                          : (_isDragging ? 'Drop file here' : 'Tap to select or Drag & Drop'),
                      style: TextStyle(
                        color: (_selectedFile != null || _isDragging) ? Colors.black : Colors.grey,
                        fontStyle: (_selectedFile != null || _isDragging) ? FontStyle.normal : FontStyle.italic,
                        fontWeight: _isDragging ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_selectedFile != null && !_isDragging)
                    const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _selectedFile == null ? null : _startTransfer,
            icon: const Icon(Icons.send),
            label: const Text('Send File'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: const Color(0xFF19231a),
              disabledBackgroundColor: Colors.grey.shade300,
            ),
          ),
        ),
      ],
    );
  }
}
