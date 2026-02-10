import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}

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
  final String? expectedSha256;

  // For sender
  File? sourceFile;

  // For receiver
  IOSink? writeSink;
  String? tempPath;
  int bytesReceived = 0;
  ByteConversionSink? hashInput;
  _DigestSink? hashDigestSink;
  Timer? acceptTimeoutTimer;
  Timer? inactivityTimer;

  FileTransferSession({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.isSender,
    this.expectedSha256,
    this.sourceFile,
  });
}

class FileTransferService {
  static final Logger _log = Logger('FileTransferService');
  static const String _msgMetadata = 'metadata';
  static const String _msgAccept = 'accept';
  static const String _msgReject = 'reject';
  static const String _msgCancel = 'cancel';
  static const String _msgEof = 'eof';
  static const int _maxFileSizeBytes = 512 * 1024 * 1024; // 512 MB
  static const Duration _acceptTimeout = Duration(seconds: 30);
  static const Duration _inactivityTimeout = Duration(seconds: 30);

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
    _webrtcManager.onFileMessage.listen(_handleFileMessage);
    _webrtcManager.onFileChannelState.listen(_handleFileChannelState);
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
    if (size > _maxFileSizeBytes) {
      throw Exception(
        'File exceeds max size (${_maxFileSizeBytes ~/ (1024 * 1024)} MB)',
      );
    }
    final name = file.uri.pathSegments.last;
    final id = DateTime.now().millisecondsSinceEpoch
        .toString(); // Simple ID for v1

    _log.info('FileTransfer: Calculating SHA-256 for $name');
    final sha256Hex = await Isolate.run(() => _computeSha256OnPath(file.path));

    _currentSession = FileTransferSession(
      id: id,
      fileName: name,
      fileSize: size,
      isSender: true,
      expectedSha256: sha256Hex,
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
      'type': _msgMetadata,
      'id': id,
      'name': name,
      'size': size,
      'sha256': sha256Hex,
    };

    await _webrtcManager.sendFileMessage(jsonEncode(offerMsg));
    _startAcceptTimeout();
  }

  // Better implementation of _startTransfer with backpressure
  Future<void> _startTransferRobust() async {
    if (_currentSession == null || !_currentSession!.isSender) {
      _log.warning(
        'FileTransfer: Cannot start transfer - session is null or not a sender',
      );
      return;
    }

    _log.info(
      'FileTransfer: Starting robust transfer for ${_currentSession!.fileName}',
    );
    _updateState(_currentState.copyWith(status: TransferStatus.transferring));
    _startInactivityTimer();

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
          _log.info('FileTransfer: Buffered amount low event received');
          lowWaterCompleter.complete();
        }
      });

      while (offset < len) {
        if (_currentState.status != TransferStatus.transferring) {
          _log.warning('FileTransfer: Transfer aborted by state change');
          break;
        }

        // Backpressure Guard (Rendezvous behavior)
        int buffered = _webrtcManager.fileChannelBufferedAmount ?? 0;
        if (buffered > _highWaterMark) {
          _log.info(
            'FileTransfer: HighWaterMark reached ($buffered), pausing...',
          );
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
          _log.info('FileTransfer: Sent $offset / $len bytes');
        }
        _updateState(_currentState.copyWith(bytesTransferred: offset));
        _resetInactivityTimer();
      }

      // Send EOF
      if (_currentState.status == TransferStatus.transferring) {
        _log.info('FileTransfer: Sending EOF');
        final eofMsg = {'type': _msgEof, 'id': _currentSession!.id};
        await _webrtcManager.sendFileMessage(jsonEncode(eofMsg));
        _updateState(_currentState.copyWith(status: TransferStatus.completed));
      }
    } catch (e, st) {
      _log.severe('FileTransfer: Send error', e, st);
      await cancelTransfer(reason: 'send_error');
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
    if (_currentSession!.fileSize > _maxFileSizeBytes) {
      await rejectOffer(reason: 'size_limit');
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${_currentSession!.id}.tmp';
      _currentSession!.tempPath = tempPath;
      final file = File(tempPath);
      _currentSession!.writeSink = file.openWrite();

      final hashSink = _DigestSink();
      _currentSession!.hashDigestSink = hashSink;
      _currentSession!.hashInput = sha256.startChunkedConversion(hashSink);

      _updateState(_currentState.copyWith(status: TransferStatus.receiving));
      _startInactivityTimer();

      final acceptMsg = {'type': _msgAccept, 'id': _currentSession!.id};
      await _webrtcManager.sendFileMessage(jsonEncode(acceptMsg));
    } catch (e) {
      _endSession(error: 'Failed to prepare receive: $e');
    }
  }

  Future<void> rejectOffer({String? reason}) async {
    if (_currentSession == null) return;
    final id = _currentSession!.id;
    _endSession();

    final rejectMsg = {'type': _msgReject, 'id': id, 'reason': reason};
    await _webrtcManager.sendFileMessage(jsonEncode(rejectMsg));
  }

  Future<void> cancelTransfer({String? reason}) async {
    if (_currentSession == null) return;
    final id = _currentSession!.id;
    _endSession(error: 'Cancelled');

    final cancelMsg = {'type': _msgCancel, 'id': id, 'reason': reason};
    await _webrtcManager.sendFileMessage(jsonEncode(cancelMsg));
  }

  // --- Handlers ---

  void _handleControlMessage(String text) {
    try {
      jsonDecode(text);
    } catch (e) {
      _log.warning('FileTransfer: Error parsing control msg', e);
    }
  }

  void _handleFileMessage(String text) {
    try {
      final msg = jsonDecode(text);
      final type = msg['type'];
      final messageId = msg['id']?.toString();
      switch (type) {
        case _msgMetadata:
          _handleOffer(msg);
          break;
        case _msgAccept:
          if (_currentSession != null &&
              _currentSession!.isSender &&
              _isMatchingId(messageId)) {
            _clearAcceptTimeout();
            _startTransferRobust();
          }
          break;
        case _msgReject:
          if (_isMatchingId(messageId)) {
            _endSession(error: 'Rejected by peer');
          }
          break;
        case _msgCancel:
          if (_isMatchingId(messageId)) {
            _endSession(error: 'Cancelled by peer');
          }
          break;
        case _msgEof:
          if (_isMatchingId(messageId)) {
            _finalizeReceive();
          }
          break;
      }
    } catch (e) {
      _log.warning('FileTransfer: Error parsing file msg', e);
    }
  }

  void _handleOffer(Map<String, dynamic> msg) {
    if (_currentSession != null) {
      // Busy, auto-reject or queue? For v1, reject or ignore.
      final rejectMsg = {
        'type': _msgReject,
        'id': msg['id']?.toString(),
        'reason': 'busy',
      };
      unawaited(_webrtcManager.sendFileMessage(jsonEncode(rejectMsg)));
      return;
    }

    final id = msg['id']?.toString();
    final name = (msg['name'] as String?) ?? 'unknown';
    final size = (msg['size'] as num?)?.toInt();
    final sha256Hex = msg['sha256'] as String?;

    if (id == null ||
        size == null ||
        size > _maxFileSizeBytes ||
        sha256Hex == null) {
      final rejectMsg = {
        'type': _msgReject,
        'id': id,
        'reason': id == null
            ? 'missing_id'
            : (sha256Hex == null ? 'missing_hash' : 'size_limit'),
      };
      unawaited(_webrtcManager.sendFileMessage(jsonEncode(rejectMsg)));
      return;
    }

    _currentSession = FileTransferSession(
      id: id,
      fileName: name,
      fileSize: size,
      isSender: false,
      expectedSha256: sha256Hex,
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
    _currentSession!.hashInput?.add(chunk);
    _currentSession!.bytesReceived += chunk.length;
    _resetInactivityTimer();

    if (_currentSession!.bytesReceived > _currentSession!.fileSize) {
      _log.warning('FileTransfer: Received more data than expected');
      unawaited(cancelTransfer(reason: 'size_mismatch'));
      return;
    }

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

      _currentSession!.hashInput?.close();
      final computedSha256 = _currentSession!.hashDigestSink?.digest
          ?.toString();

      if (_currentSession!.bytesReceived != _currentSession!.fileSize) {
        throw Exception('Size mismatch');
      }

      if (_currentSession!.expectedSha256 != null &&
          computedSha256 != _currentSession!.expectedSha256) {
        throw Exception('SHA-256 mismatch');
      }

      _clearInactivityTimer();

      // Move to Downloads or Documents
      String finalPath;
      if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        finalPath = await _resolveUniquePath(
          appDir,
          _sanitizeFileName(_currentSession!.fileName),
        );
      } else {
        // On Desktop, try Downloads folder
        final downloadsDir = await getDownloadsDirectory();
        final targetDir =
            downloadsDir ?? await getApplicationDocumentsDirectory();
        finalPath = await _resolveUniquePath(
          targetDir,
          _sanitizeFileName(_currentSession!.fileName),
        );
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

      _log.info('File saved to $finalPath');
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
    try {
      _currentSession?.hashInput?.close();
    } catch (_) {}
    if (_currentSession?.tempPath != null) {
      // Delete incomplete temp file
      try {
        File(_currentSession!.tempPath!).delete();
      } catch (_) {}
    }
    _clearAcceptTimeout();
    _clearInactivityTimer();

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

  void _handleFileChannelState(RTCDataChannelState state) {
    if (_currentSession == null) return;
    switch (state) {
      case RTCDataChannelState.RTCDataChannelClosing:
        _endSession(error: 'File channel closing');
        break;
      case RTCDataChannelState.RTCDataChannelClosed:
        _endSession(error: 'File channel closed');
        break;
      case RTCDataChannelState.RTCDataChannelConnecting:
      case RTCDataChannelState.RTCDataChannelOpen:
        break;
    }
  }

  void _startAcceptTimeout() {
    _clearAcceptTimeout();
    _currentSession?.acceptTimeoutTimer = Timer(_acceptTimeout, () {
      cancelTransfer(reason: 'accept_timeout');
    });
  }

  void _clearAcceptTimeout() {
    _currentSession?.acceptTimeoutTimer?.cancel();
    _currentSession?.acceptTimeoutTimer = null;
  }

  void _startInactivityTimer() {
    _clearInactivityTimer();
    _currentSession?.inactivityTimer = Timer(_inactivityTimeout, () {
      cancelTransfer(reason: 'inactivity_timeout');
    });
  }

  void _resetInactivityTimer() {
    if (_currentSession?.inactivityTimer == null) return;
    _startInactivityTimer();
  }

  void _clearInactivityTimer() {
    _currentSession?.inactivityTimer?.cancel();
    _currentSession?.inactivityTimer = null;
  }

  bool _isMatchingId(String? messageId) {
    return _currentSession != null && messageId == _currentSession!.id;
  }
}

Future<String> _computeSha256OnPath(String path) async {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  final raf = await File(path).open(mode: FileMode.read);
  try {
    while (true) {
      final chunk = await raf.read(FileTransferService._chunkSize);
      if (chunk.isEmpty) break;
      input.add(chunk);
    }
  } finally {
    await raf.close();
    input.close();
  }
  return sink.digest.toString();
}

String _sanitizeFileName(String raw) {
  final lastSegment = raw.split(RegExp(r'[\\/]+')).last;
  final sanitized = lastSegment.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
  final trimmed = sanitized.trim();
  return trimmed.isEmpty ? 'file' : trimmed;
}

Future<String> _resolveUniquePath(Directory dir, String fileName) async {
  final separatorIndex = fileName.lastIndexOf('.');
  final baseName = separatorIndex > 0
      ? fileName.substring(0, separatorIndex)
      : fileName;
  final extension = separatorIndex > 0
      ? fileName.substring(separatorIndex)
      : '';

  var candidate = File('${dir.path}/$fileName');
  var counter = 1;
  while (await candidate.exists()) {
    final nextName = '$baseName ($counter)$extension';
    candidate = File('${dir.path}/$nextName');
    counter += 1;
  }
  return candidate.path;
}
