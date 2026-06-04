import 'dart:async';

import 'package:application/src/features/session/application/serial_task_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> _drainEventLoop([int iterations = 20]) async {
    for (var i = 0; i < iterations; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('processes queued items in FIFO order', () async {
    final processed = <int>[];
    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    queue.enqueue(3);

    await _drainEventLoop();

    expect(processed, <int>[1, 2, 3]);
    queue.dispose();
  });

  test('continues processing items after processor error', () async {
    final processed = <int>[];
    final errors = <Object>[];

    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        if (item == 2) {
          throw StateError('boom');
        }
        processed.add(item);
      },
      onError: (error, _) {
        errors.add(error);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    queue.enqueue(3);

    await _drainEventLoop();

    expect(processed, <int>[1, 3]);
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    queue.dispose();
  });

  test('items queued during processing are still processed serially', () async {
    final processed = <int>[];
    final gate = Completer<void>();

    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        if (item == 1) {
          await gate.future;
        }
        processed.add(item);
      },
    );

    queue.enqueue(1);
    await _drainEventLoop();

    queue.enqueue(2);
    queue.enqueue(3);
    gate.complete();

    await _drainEventLoop();

    expect(processed, <int>[1, 2, 3]);
    queue.dispose();
  });

  test('clear removes pending items but keeps in-flight work', () async {
    final processed = <int>[];
    final gate = Completer<void>();

    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        if (item == 1) {
          await gate.future;
        }
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    await _drainEventLoop();

    queue.clear();
    gate.complete();

    await _drainEventLoop();

    expect(processed, <int>[1]);
    queue.dispose();
  });

  test('dispose drops pending items and ignores new enqueues', () async {
    final processed = <int>[];
    final gate = Completer<void>();

    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        if (item == 1) {
          await gate.future;
        }
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    await _drainEventLoop();

    queue.dispose();
    queue.enqueue(3);
    gate.complete();

    await _drainEventLoop();

    expect(processed, <int>[1]);
  });

  test('queue handles multiple batches after becoming idle', () async {
    final processed = <int>[];
    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    await _drainEventLoop();
    expect(processed, <int>[1, 2]);

    queue.enqueue(3);
    queue.enqueue(4);
    await _drainEventLoop();
    expect(processed, <int>[1, 2, 3, 4]);

    queue.dispose();
  });

  test('clear before processing starts drops queued items', () async {
    final processed = <int>[];
    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    queue.clear();

    await _drainEventLoop();

    expect(processed, isEmpty);
    queue.dispose();
  });

  test('enqueue after clear processes only newly added items', () async {
    final processed = <int>[];
    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.clear();
    queue.enqueue(2);

    await _drainEventLoop();

    expect(processed, <int>[2]);
    queue.dispose();
  });

  test('processing is not concurrent', () async {
    var inFlight = 0;
    var maxInFlight = 0;

    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        inFlight += 1;
        if (inFlight > maxInFlight) {
          maxInFlight = inFlight;
        }

        await Future<void>.delayed(Duration.zero);
        inFlight -= 1;
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    queue.enqueue(3);
    queue.enqueue(4);
    queue.enqueue(5);

    await _drainEventLoop(40);

    expect(maxInFlight, 1);
    queue.dispose();
  });

  test('errors are swallowed when no error handler is provided', () async {
    final processed = <int>[];
    final queue = SerialTaskQueue<int>(
      processor: (item) async {
        if (item == 2) {
          throw StateError('boom');
        }
        processed.add(item);
      },
    );

    queue.enqueue(1);
    queue.enqueue(2);
    queue.enqueue(3);

    await _drainEventLoop();

    expect(processed, <int>[1, 3]);
    queue.dispose();
  });
}
