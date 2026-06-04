import 'dart:async';

import 'package:application/src/features/session/application/session_control_protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  DateTime _fakeNowFrom(FakeAsync async) {
    return DateTime.fromMillisecondsSinceEpoch(async.elapsed.inMilliseconds);
  }

  test('sends heartbeat pings every 5 seconds', () {
    fakeAsync((async) {
      final sentPings = <String>[];
      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.ping_interval'),
        sendPing: (ts) async => sentPings.add(ts),
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 15));

      expect(sentPings, hasLength(3));
      protocol.dispose();
    });
  });

  test('heartbeat timeout triggers callback once and stops heartbeats', () {
    fakeAsync((async) {
      var pingCount = 0;
      var timeoutCount = 0;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.timeout'),
        sendPing: (_) async {
          pingCount += 1;
        },
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {
          timeoutCount += 1;
        },
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 20));

      expect(pingCount, 3);
      expect(timeoutCount, 1);

      async.elapse(const Duration(seconds: 10));
      expect(pingCount, 3);
      expect(timeoutCount, 1);

      protocol.dispose();
    });
  });

  test('pong updates heartbeat freshness and prevents timeout', () {
    fakeAsync((async) {
      var pingCount = 0;
      var timeoutCount = 0;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.pong_refresh'),
        sendPing: (_) async {
          pingCount += 1;
        },
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {
          timeoutCount += 1;
        },
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 15));
      expect(pingCount, 3);
      expect(timeoutCount, 0);

      protocol.handlePong();
      async.elapse(const Duration(seconds: 5));

      expect(pingCount, 4);
      expect(timeoutCount, 0);

      protocol.dispose();
    });
  });

  test(
    'session closed message sends generated id and local disconnect reason',
    () async {
      String? sentId;
      String? sentReason;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.send_closed'),
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {
          sentId = id;
          sentReason = reason;
        },
        onHeartbeatTimeout: () async {},
      );

      await protocol.sendSessionClosedMessage();

      expect(sentId, isNotNull);
      expect(sentId, matches(RegExp(r'^\d+$')));
      expect(sentReason, 'local_disconnect');

      protocol.dispose();
    },
  );

  test('matching session-close ack suppresses unacknowledged warning', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final logger = Logger('session_control_protocol_test.ack_match');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      String? sentId;
      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {
          sentId = id;
        },
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      protocol.handleSessionClosedAck(sentId);
      async.elapse(const Duration(seconds: 5));

      expect(warnings, isEmpty);
      protocol.dispose();
    });
  });

  test('non-matching session-close ack logs unacknowledged warning', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final logger = Logger('session_control_protocol_test.ack_mismatch');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      protocol.handleSessionClosedAck('wrong-id');
      async.elapse(const Duration(seconds: 5));

      expect(warnings, contains('Session close was not acknowledged'));
      protocol.dispose();
    });
  });

  test('sendSessionClosedMessage logs warning if send fails', () async {
    final warnings = <String>[];
    final logger = Logger('session_control_protocol_test.send_failure');
    logger.onRecord.listen((record) {
      if (record.level >= Level.WARNING) {
        warnings.add(record.message);
      }
    });

    final protocol = SessionControlProtocol(
      log: logger,
      sendPing: (_) async {},
      sendSessionClosed: ({required String id, String? reason}) {
        throw StateError('simulated failure');
      },
      onHeartbeatTimeout: () async {},
    );

    await protocol.sendSessionClosedMessage();

    expect(warnings, contains('Session close message failed'));
    protocol.dispose();
  });

  test('restarting heartbeat does not create duplicate timers', () {
    fakeAsync((async) {
      var pingCount = 0;
      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.restart_heartbeat'),
        sendPing: (_) async {
          pingCount += 1;
        },
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 2));
      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 15));

      expect(pingCount, 3);
      protocol.dispose();
    });
  });

  test('stopHeartbeat prevents further pings and timeout callback', () {
    fakeAsync((async) {
      var pingCount = 0;
      var timeoutCount = 0;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.stop_heartbeat'),
        sendPing: (_) async {
          pingCount += 1;
        },
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {
          timeoutCount += 1;
        },
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 5));
      protocol.stopHeartbeat();

      async.elapse(const Duration(seconds: 30));

      expect(pingCount, 1);
      expect(timeoutCount, 0);
      protocol.dispose();
    });
  });

  test('heartbeat timeout happens only after exceeding 15 seconds', () {
    fakeAsync((async) {
      var timeoutCount = 0;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.timeout_boundary'),
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {
          timeoutCount += 1;
        },
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 15));
      expect(timeoutCount, 0);

      async.elapse(const Duration(seconds: 5));
      expect(timeoutCount, 1);
      protocol.dispose();
    });
  });

  test('dispose cancels pending session-close ack warning timer', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final logger = Logger('session_control_protocol_test.dispose_ack_timer');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();
      protocol.dispose();

      async.elapse(const Duration(seconds: 5));
      expect(warnings, isEmpty);
    });
  });

  test('acknowledging an old session-close id does not ack a newer one', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final sentIds = <String>[];
      final logger = Logger('session_control_protocol_test.rotate_close_id');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {
          sentIds.add(id);
        },
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      async.elapse(const Duration(milliseconds: 1));
      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      expect(sentIds, hasLength(2));
      expect(sentIds[0], isNot(sentIds[1]));

      protocol.handleSessionClosedAck(sentIds[0]);
      async.elapse(const Duration(seconds: 5));

      expect(warnings, contains('Session close was not acknowledged'));
      protocol.dispose();
    });
  });

  test('null session-close ack id is ignored', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final logger = Logger('session_control_protocol_test.null_ack');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      protocol.handleSessionClosedAck(null);
      async.elapse(const Duration(seconds: 5));

      expect(warnings, contains('Session close was not acknowledged'));
      protocol.dispose();
    });
  });

  test('stopHeartbeat is safe before heartbeat starts', () {
    fakeAsync((async) {
      var pingCount = 0;
      var timeoutCount = 0;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.stop_without_start'),
        sendPing: (_) async {
          pingCount += 1;
        },
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {
          timeoutCount += 1;
        },
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.stopHeartbeat();
      protocol.stopHeartbeat();
      async.elapse(const Duration(seconds: 20));

      expect(pingCount, 0);
      expect(timeoutCount, 0);
      protocol.dispose();
    });
  });

  test('heartbeat can restart after timeout and emit pings again', () {
    fakeAsync((async) {
      var pingCount = 0;
      var timeoutCount = 0;

      final protocol = SessionControlProtocol(
        log: Logger('session_control_protocol_test.restart_after_timeout'),
        sendPing: (_) async {
          pingCount += 1;
        },
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {
          timeoutCount += 1;
        },
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 20));
      expect(pingCount, 3);
      expect(timeoutCount, 1);

      protocol.startHeartbeat();
      async.elapse(const Duration(seconds: 5));

      expect(pingCount, 4);
      expect(timeoutCount, 1);
      protocol.dispose();
    });
  });

  test(
    'pong just before timeout postpones timeout until threshold is crossed',
    () {
      fakeAsync((async) {
        var pingCount = 0;
        var timeoutCount = 0;

        final protocol = SessionControlProtocol(
          log: Logger('session_control_protocol_test.pong_postpones_timeout'),
          sendPing: (_) async {
            pingCount += 1;
          },
          sendSessionClosed: ({required String id, String? reason}) async {},
          onHeartbeatTimeout: () async {
            timeoutCount += 1;
          },
          nowProvider: () => _fakeNowFrom(async),
        );

        protocol.startHeartbeat();
        async.elapse(const Duration(seconds: 14));
        expect(pingCount, 2);

        protocol.handlePong();
        async.elapse(const Duration(seconds: 15));

        expect(pingCount, 5);
        expect(timeoutCount, 0);

        async.elapse(const Duration(seconds: 1));
        expect(timeoutCount, 1);
        protocol.dispose();
      });
    },
  );

  test('second close send resets previous acknowledged state', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final sentIds = <String>[];
      final logger = Logger('session_control_protocol_test.reset_ack_state');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {
          sentIds.add(id);
        },
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();
      protocol.handleSessionClosedAck(sentIds.first);

      async.elapse(const Duration(milliseconds: 1));
      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      expect(sentIds, hasLength(2));
      expect(sentIds[0], isNot(sentIds[1]));

      async.elapse(const Duration(seconds: 5));
      expect(warnings, contains('Session close was not acknowledged'));
      protocol.dispose();
    });
  });

  test('acknowledgement received before close send is ignored', () {
    fakeAsync((async) {
      final warnings = <String>[];
      final logger = Logger('session_control_protocol_test.early_ack_ignored');
      logger.onRecord.listen((record) {
        if (record.level >= Level.WARNING) {
          warnings.add(record.message);
        }
      });

      final protocol = SessionControlProtocol(
        log: logger,
        sendPing: (_) async {},
        sendSessionClosed: ({required String id, String? reason}) async {},
        onHeartbeatTimeout: () async {},
        nowProvider: () => _fakeNowFrom(async),
      );

      protocol.handleSessionClosedAck('early-id');
      unawaited(protocol.sendSessionClosedMessage());
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5));
      expect(warnings, contains('Session close was not acknowledged'));
      protocol.dispose();
    });
  });
}
