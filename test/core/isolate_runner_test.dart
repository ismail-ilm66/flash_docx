import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flutter_test/flutter_test.dart';

int _square(int v) => v * v;
int _boom(int v) => throw StateError('boom $v');

void main() {
  test('runs jobs serially and in order', () async {
    final r = IsolateRunner();
    final results = await Future.wait([
      r.run(_square, 2),
      r.run(_square, 3),
      r.run(_square, 4),
    ]);
    expect(results, [4, 9, 16]);
  });

  test('a failing job does not block the queue', () async {
    final r = IsolateRunner();
    final failing = r.run(_boom, 1);
    final ok = r.run(_square, 5);
    await expectLater(failing, throwsStateError);
    expect(await ok, 25);
  });

  test('interactive jobs start before queued background jobs (P0-4)', () async {
    final r = IsolateRunner();
    final order = <String>[];
    final jobs = [
      r.run(_slow, 50).then((_) => order.add('bg1')), // starts at once
      r.run(_square, 2).then((_) => order.add('bg2')),
      r.run(_square, 3).then((_) => order.add('bg3')),
      r.run(_square, 4, priority: JobPriority.interactive).then((_) => order.add('ui')),
    ];
    await Future.wait(jobs);
    expect(order, ['bg1', 'ui', 'bg2', 'bg3']);
  });

  test('a cancelled job is dropped before it starts', () async {
    final r = IsolateRunner();
    final token = CancelToken();
    final first = r.run(_slow, 50);
    final stale = r.run(_square, 9, priority: JobPriority.interactive, cancel: token);
    token.cancel();
    await expectLater(stale, throwsA(isA<JobCancelled>()));
    await first;
    expect(await r.run(_square, 3), 9);
  });
}

int _slow(int ms) {
  final sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < ms) {}
  return ms;
}
