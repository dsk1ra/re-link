import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:path_provider/path_provider.dart';

enum TransferStatus {
  idle,
  offering, // Sender waiting for accept
  offered, // Receiver deciding
  transferring,
  receiving,
  completed,
  error,
}

class FileTransferState {
  final TransferStatus status;
  final String? fileName;
  final int totalBytes;
  final int bytesTransferred;
  final String? error;

  FileTransferState({
    required this.status,
    this.fileName,
    this.totalBytes = 0,
    this.bytesTransferred = 0,
    this.error,
  });

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;

  FileTransferState copyWith({
    TransferStatus? status,
    String? fileName,
    int? totalBytes,
    int? bytesTransferred,
    String? error,
  }) {
    return FileTransferState(
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      error: error ?? this.error,
    );
  }
}

class FileTransferSession {
  final String id;
  final String fileName;
  final int fileSize;
  final bool isSender;

  // For sender
  File? sourceFile;

  // For receiver
  IOSink? writeSink;
  String? tempPath;
  int bytesReceived = 0;

  FileTransferSession({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.isSender,
    this.sourceFile,
  });
}

class FileTransferService {
  final WebRTCManager _webrtcManager;
  final StreamController<FileTransferState> _stateController =
      StreamController.broadcast();

  FileTransferSession? _currentSession;
  FileTransferState _currentState = FileTransferState(
    status: TransferStatus.idle,
  );

  // Configuration
  static const int _chunkSize = 64 * 1024; // 64 KB
  static const int _highWaterMark = 1024 * 1024; // 1 MB buffer limit
  static const int _lowWaterMark = 64 * 1024; // 64 KB threshold to resume

  Stream<FileTransferState> get onStateChange => _stateController.stream;
  FileTransferState get currentState => _currentState;

  FileTransferService(this._webrtcManager) {
    _webrtcManager.onMessage.listen(_handleControlMessage);
    _webrtcManager.onFileChunk.listen(_handleFileChunk);
  }

  void _updateState(FileTransferState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  // --- Sender Methods ---

  Future<void> sendOffer(File file) async {
    if (_currentSession != null) {
      throw Exception('Transfer already in progress');
    }

    final size = await file.length();
    final name = file.uri.pathSegments.last;
    final id = DateTime.now().millisecondsSinceEpoch
        .toString(); // Simple ID for v1

    _currentSession = FileTransferSession(
      id: id,
      fileName: name,
      fileSize: size,
      isSender: true,
      sourceFile: file,
    );

    _updateState(
      FileTransferState(
        status: TransferStatus.offering,
        fileName: name,
        totalBytes: size,
      ),
    );

    final offerMsg = {
      'type': 'file_offer',
      'id': id,
      'name': name,
      'size': size,
    };

    await _webrtcManager.sendControlMessage(jsonEncode(offerMsg));
  }

  // Better implementation of _startTransfer with backpressure
  Future<void> _startTransferRobust() async {
    if (_currentSession == null || !_currentSession!.isSender) {
      print(
        'FileTransfer: Cannot start transfer - session is null or not a sender',
      );
      return;
    }

    print(
      'FileTransfer: Starting robust transfer for ${_currentSession!.fileName}',
    );
    _updateState(_currentState.copyWith(status: TransferStatus.transferring));

    RandomAccessFile? raf;
    try {
      raf = await _currentSession!.sourceFile!.open(mode: FileMode.read);
      final len = _currentSession!.fileSize;
      int offset = 0;

      // Setup Rendezvous/CSP backpressure
      Completer? lowWaterCompleter;
      _webrtcManager.setFileChannelBufferedAmountLowThreshold(_lowWaterMark);
      _webrtcManager.setOnFileChannelBufferedAmountLow(() {
        if (lowWaterCompleter != null && !lowWaterCompleter.isCompleted) {
          print('FileTransfer: Buffered amount low event received');
          lowWaterCompleter.complete();
        }
      });

      while (offset < len) {
        if (_currentState.status != TransferStatus.transferring) {
          print('FileTransfer: Transfer aborted by state change');
          break;
        }

        // Backpressure Guard (Rendezvous behavior)
        int buffered = _webrtcManager.fileChannelBufferedAmount ?? 0;
        if (buffered > _highWaterMark) {
          print('FileTransfer: HighWaterMark reached ($buffered), pausing...');
          lowWaterCompleter = Completer();
          await lowWaterCompleter.future;
        }

        // Read chunk
        final bytesToRead = (len - offset) > _chunkSize
            ? _chunkSize
            : (len - offset);
        final chunk = await raf.read(bytesToRead);

        // Send
        await _webrtcManager.sendFileChunk(chunk);

        offset += chunk.length;
        if (offset % (1024 * 1024) == 0 || offset == len) {
          print('FileTransfer: Sent $offset / $len bytes');
        }
        _updateState(_currentState.copyWith(bytesTransferred: offset));
      }

      // Send complete message
      if (_currentState.status == TransferStatus.transferring) {
        print('FileTransfer: Sending file_complete signal');
        final completeMsg = {
          'type': 'file_complete',
          'id': _currentSession!.id,
        };
        await _webrtcManager.sendControlMessage(jsonEncode(completeMsg));
        _updateState(_currentState.copyWith(status: TransferStatus.completed));
      }
    } catch (e) {
      print('FileTransfer: Send error: $e');
      _endSession(error: 'Send error: $e');
    } finally {
      await raf?.close();
      if (_currentState.status == TransferStatus.completed) {
        _currentSession = null; // Done
      }
    }
  }

  // --- Receiver Methods ---

  Future<void> acceptOffer() async {
    if (_currentSession == null || _currentSession!.isSender) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${_currentSession!.id}.tmp';
      _currentSession!.tempPath = tempPath;
      final file = File(tempPath);
      _currentSession!.writeSink = file.openWrite();

      _updateState(_currentState.copyWith(status: TransferStatus.receiving));

      final acceptMsg = {'type': 'file_accept', 'id': _currentSession!.id};
      await _webrtcManager.sendControlMessage(jsonEncode(acceptMsg));
    } catch (e) {
      _endSession(error: 'Failed to prepare receive: $e');
    }
  }

  Future<void> rejectOffer() async {
    if (_currentSession == null) return;
    final id = _currentSession!.id;
    _endSession();

    final cancelMsg = {'type': 'file_cancel', 'id': id};
    await _webrtcManager.sendControlMessage(jsonEncode(cancelMsg));
  }

  // --- Handlers ---

  void _handleControlMessage(String text) {
    try {
      final msg = jsonDecode(text);
      final type = msg['type'];

      switch (type) {
        case 'file_offer':
          _handleOffer(msg);
          break;
        case 'file_accept':
          if (_currentSession != null && _currentSession!.isSender) {
            _startTransferRobust();
          }
          break;
        case 'file_complete':
          _finalizeReceive();
          break;
        case 'file_cancel':
          _endSession(error: 'Cancelled by peer');
          break;
      }
    } catch (e) {
      print('FileTransfer: Error parsing control msg: $e');
    }
  }

  void _handleOffer(Map<String, dynamic> msg) {
    if (_currentSession != null) {
      // Busy, auto-reject or queue? For v1, reject or ignore.
      return;
    }

    final id = msg['id'];
    final name = msg['name'];
    final size = msg['size'];

    _currentSession = FileTransferSession(
      id: id,
      fileName: name,
      fileSize: size,
      isSender: false,
    );

    _updateState(
      FileTransferState(
        status: TransferStatus.offered,
        fileName: name,
        totalBytes: size,
      ),
    );
  }

  void _handleFileChunk(List<int> chunk) {
    if (_currentSession == null ||
        _currentState.status != TransferStatus.receiving ||
        _currentSession!.writeSink == null) {
      return;
    }

    _currentSession!.writeSink!.add(chunk);
    _currentSession!.bytesReceived += chunk.length;

    _updateState(
      _currentState.copyWith(bytesTransferred: _currentSession!.bytesReceived),
    );
  }

  Future<void> _finalizeReceive() async {
    if (_currentSession == null || _currentSession!.writeSink == null) return;

    try {
      await _currentSession!.writeSink!.flush();
      await _currentSession!.writeSink!.close();
      _currentSession!.writeSink = null;

      // Move to Downloads or Documents
      String finalPath;
      if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        finalPath = '${appDir.path}/${_currentSession!.fileName}';
      } else {
        // On Desktop, try Downloads folder
        final downloadsDir = await getDownloadsDirectory();
        finalPath =
            '${downloadsDir?.path ?? (await getApplicationDocumentsDirectory()).path}/${_currentSession!.fileName}';
      }

      // Rename or Copy
      final tempFile = File(_currentSession!.tempPath!);
      await tempFile.copy(finalPath);
      await tempFile.delete();

      _updateState(
        _currentState.copyWith(
          status: TransferStatus.completed,
          bytesTransferred: _currentSession!.fileSize,
          error: null,
        ),
      );

      print('File saved to $finalPath');
      _currentSession = null;
    } catch (e) {
      _endSession(error: 'Finalization failed: $e');
    }
  }

  void _endSession({String? error}) {
    // Close resources
    if (_currentSession?.writeSink != null) {
      try {
        _currentSession!.writeSink!.close();
      } catch (_) {}
    }
    if (_currentSession?.tempPath != null) {
      // Delete incomplete temp file
      try {
        File(_currentSession!.tempPath!).delete();
      } catch (_) {}
    }

    _currentSession = null;
    _updateState(
      _currentState.copyWith(
        status: error != null ? TransferStatus.error : TransferStatus.idle,
        error: error,
      ),
    );
  }

  void dispose() {
    _stateController.close();
  }
}
