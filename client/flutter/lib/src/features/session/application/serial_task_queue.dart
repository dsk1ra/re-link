import 'dart:async';

typedef AsyncTaskProcessor<T> = Future<void> Function(T item);
typedef AsyncTaskErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class SerialTaskQueue<T> {
  SerialTaskQueue({
    required AsyncTaskProcessor<T> processor,
    AsyncTaskErrorHandler? onError,
  }) : _processor = processor,
       _onError = onError;

  final AsyncTaskProcessor<T> _processor;
  final AsyncTaskErrorHandler? _onError;
  final List<T> _items = <T>[];

  int get length => _items.length;

  bool _isProcessing = false;
  bool _isScheduled = false;
  bool _isDisposed = false;

  void enqueue(T item) {
    if (_isDisposed) return;
    _items.add(item);
    _scheduleProcessing();
  }

  void clear() {
    _items.clear();
  }

  void dispose() {
    _isDisposed = true;
    _items.clear();
  }

  void _scheduleProcessing() {
    if (_isDisposed || _isProcessing || _isScheduled) return;

    _isScheduled = true;
    scheduleMicrotask(() {
      _isScheduled = false;
      unawaited(_process());
    });
  }

  Future<void> _process() async {
    if (_isDisposed || _isProcessing || _items.isEmpty) return;

    _isProcessing = true;
    try {
      while (_items.isNotEmpty && !_isDisposed) {
        final item = _items.removeAt(0);
        try {
          await _processor(item);
        } catch (error, stackTrace) {
          _onError?.call(error, stackTrace);
        }
      }
    } finally {
      _isProcessing = false;
      _scheduleProcessing();
    }
  }
}
