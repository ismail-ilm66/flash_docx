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
}
