import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/sync/sync_task_queue.dart';

void main() {
  test('runs submitted sync tasks one at a time in submission order', () async {
    final queue = SyncTaskQueue();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var activeTasks = 0;
    var maxActiveTasks = 0;

    final first = queue.run(() async {
      activeTasks++;
      maxActiveTasks = activeTasks;
      firstStarted.complete();
      await releaseFirst.future;
      activeTasks--;
      return 1;
    });

    await firstStarted.future;

    final second = queue.run(() async {
      activeTasks++;
      if (activeTasks > maxActiveTasks) maxActiveTasks = activeTasks;
      activeTasks--;
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(maxActiveTasks, 1);

    releaseFirst.complete();

    expect(await Future.wait([first, second]), [1, 2]);
    expect(maxActiveTasks, 1);
  });

  test('continues with queued tasks after a task fails', () async {
    final queue = SyncTaskQueue();

    final failed = queue.run<int>(() async => throw StateError('failed'));
    final next = queue.run(() async => 2);

    await expectLater(failed, throwsStateError);
    expect(await next, 2);
  });
}
