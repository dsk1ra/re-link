import '../signaling/signaling_client.dart';

/// Standard interface for a simple message queue style backend.
abstract class MessageQueueBackend {
  Future<void> produce(String payload);
  Future<String?> consume();
  Future<List<String>> list();
  Future<void> dispose();
}

/// A message queue facade over the HTTP signaling server.
/// Since the server API does not support deletion,
/// consumption is emulated locally: once a message timestamp is consumed
/// it is hidden from subsequent list() calls.
class SignalingQueueBackend implements MessageQueueBackend {
  final SignalingClient _client;
  final Set<int> _consumed = <int>{};
  List<_CachedMsg> _cache = [];

  SignalingQueueBackend(this._client);

  Future<void> init({String label = 'flutter'}) => _client.register(deviceLabel: label);

  Future<void> _refresh() async {
    final msgs = await _client.pollMessages();
    _cache = msgs
        .map((m) => _CachedMsg(
              id: m.createdAt.millisecondsSinceEpoch,
              from: m.from,
              payload: m.payload,
              createdAt: m.createdAt,
            ))
        .toList();
    // cache is newest first already per pollMessages sort
  }

  @override
  Future<void> produce(String payload) async {
    await _client.sendToSelf(payload);
    await _refresh();
  }

  @override
  Future<String?> consume() async {
    if (_cache.isEmpty) await _refresh();
    if (_cache.isEmpty) return null;
    // Consume oldest (queue semantics): list is newest first, so oldest is last.
    for (var i = _cache.length - 1; i >= 0; i--) {
      final m = _cache[i];
      if (_consumed.add(m.id)) {
        return m.payload;
      }
    }
    // All cached messages consumed; try a refresh once.
    await _refresh();
    for (var i = _cache.length - 1; i >= 0; i--) {
      final m = _cache[i];
      if (_consumed.add(m.id)) {
        return m.payload;
      }
    }
    return null;
  }

  @override
  Future<List<String>> list() async {
    await _refresh();
    return _cache
        .where((m) => !_consumed.contains(m.id))
        .map((m) => '[${m.from.substring(0, 8)}] ${m.payload}')
        .toList();
  }

  @override
  Future<void> dispose() => _client.dispose();
}

class _CachedMsg {
  final int id; // createdAt ms epoch
  final String from;
  final String payload;
  final DateTime createdAt;
  _CachedMsg({required this.id, required this.from, required this.payload, required this.createdAt});
}
