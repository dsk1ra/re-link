import 'dart:async';
import 'dart:io';

import 'package:application/src/rust/api/file_transfer.dart'
    as rust_file_transfer;
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

enum TransferStatus {
  idle,
  offering,
  offered,
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

class FileTransferService {
  static final Logger _log = Logger('FileTransferService');
  static const Duration _syncInterval = Duration(milliseconds: 120);

  final WebRTCManager _webrtcManager;
  final StreamController<FileTransferState> _stateController =
      StreamController.broadcast();
  StreamSubscription<RTCDataChannelState>? _fileChannelStateSubscription;
  Timer? _syncTimer;
  bool _syncInFlight = false;

  FileTransferState _currentState = FileTransferState(
    status: TransferStatus.idle,
  );
  bool _isDisposed = false;

  Stream<FileTransferState> get onStateChange => _stateController.stream;
  FileTransferState get currentState => _currentState;

  FileTransferService(this._webrtcManager) {
    rust_file_transfer.initTransfer(connectionId: _webrtcManager.connectionId);

    _fileChannelStateSubscription = _webrtcManager.onFileChannelState.listen(
      _handleFileChannelState,
    );

    _syncTimer = Timer.periodic(
      _syncInterval,
      (_) => unawaited(_syncFromRust()),
    );
    unawaited(_syncFromRust());
  }

  void _updateState(FileTransferState newState) {
    if (_isDisposed || _stateController.isClosed) return;
    _currentState = newState;
    _stateController.add(newState);
  }

  Future<void> sendOffer(File file) async {
    if (!_webrtcManager.isConnected) {
      _updateState(
        _currentState.copyWith(
          status: TransferStatus.error,
          error: 'Not connected to peer',
        ),
      );
      return;
    }

    if (_webrtcManager.fileChannelState !=
        RTCDataChannelState.RTCDataChannelStateOpen) {
      _updateState(
        _currentState.copyWith(
          status: TransferStatus.error,
          error: 'File channel is not open',
        ),
      );
      return;
    }

    try {
      await rust_file_transfer.sendOffer(
        connectionId: _webrtcManager.connectionId,
        filePath: file.path,
      );
      await _syncFromRust();
    } catch (_) {
      _log.warning('File transfer offer failed');
      _updateState(
        _currentState.copyWith(
          status: TransferStatus.error,
          error: 'Failed to start file transfer',
        ),
      );
    }
  }

  Future<void> syncNow() async {
    await _syncFromRust();
  }

  Future<void> acceptOffer() async {
    final saveDir = await _defaultSaveDirectory();
    await rust_file_transfer.acceptOffer(
      connectionId: _webrtcManager.connectionId,
      saveDir: saveDir.path,
    );
    await _syncFromRust();
  }

  Future<void> rejectOffer({String? reason}) async {
    await rust_file_transfer.rejectOffer(
      connectionId: _webrtcManager.connectionId,
      reason: reason,
    );
    await _syncFromRust();
  }

  Future<void> cancelTransfer({String? reason}) async {
    try {
      await rust_file_transfer.cancelTransfer(
        connectionId: _webrtcManager.connectionId,
        reason: reason,
      );
      await _syncFromRust();
    } catch (_) {
      _log.warning('File transfer cancellation failed');
      _updateState(
        _currentState.copyWith(
          status: TransferStatus.error,
          error: 'Failed to cancel file transfer',
        ),
      );
    }
  }

  Future<void> _syncFromRust() async {
    if (_isDisposed || _syncInFlight) {
      return;
    }

    _syncInFlight = true;
    try {
      final states = await rust_file_transfer.drainStates(
        connectionId: _webrtcManager.connectionId,
      );
      for (final state in states) {
        final mapped = _fromRustState(state);
        _updateState(mapped);
      }
    } catch (_) {
      _log.warning('File transfer state sync failed');
    } finally {
      _syncInFlight = false;
    }
  }

  FileTransferState _fromRustState(
    rust_file_transfer.FileTransferStateDto dto,
  ) {
    return FileTransferState(
      status: _fromRustStatus(dto.status),
      fileName: dto.fileName,
      totalBytes: dto.totalBytes.toInt(),
      bytesTransferred: dto.bytesTransferred.toInt(),
      error: dto.error,
    );
  }

  TransferStatus _fromRustStatus(rust_file_transfer.TransferStatusDto status) {
    switch (status) {
      case rust_file_transfer.TransferStatusDto.idle:
        return TransferStatus.idle;
      case rust_file_transfer.TransferStatusDto.offering:
        return TransferStatus.offering;
      case rust_file_transfer.TransferStatusDto.offered:
        return TransferStatus.offered;
      case rust_file_transfer.TransferStatusDto.transferring:
        return TransferStatus.transferring;
      case rust_file_transfer.TransferStatusDto.receiving:
        return TransferStatus.receiving;
      case rust_file_transfer.TransferStatusDto.completed:
        return TransferStatus.completed;
      case rust_file_transfer.TransferStatusDto.error:
        return TransferStatus.error;
    }
  }

  Future<Directory> _defaultSaveDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    final downloadsDir = await getDownloadsDirectory();
    return downloadsDir ?? getApplicationDocumentsDirectory();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _fileChannelStateSubscription?.cancel();
    _syncTimer?.cancel();

    _fileChannelStateSubscription = null;
    _syncTimer = null;

    unawaited(
      rust_file_transfer.disposeTransfer(
        connectionId: _webrtcManager.connectionId,
      ),
    );

    _stateController.close();
  }

  void _handleFileChannelState(RTCDataChannelState state) {
    switch (state) {
      case RTCDataChannelState.RTCDataChannelStateClosing:
        unawaited(cancelTransfer(reason: 'file_channel_closing'));
        break;
      case RTCDataChannelState.RTCDataChannelStateClosed:
        unawaited(cancelTransfer(reason: 'file_channel_closed'));
        break;
      case RTCDataChannelState.RTCDataChannelStateConnecting:
      case RTCDataChannelState.RTCDataChannelStateOpen:
        break;
    }
  }
}
