import 'dart:async';

import 'package:flash_dox/features/scanner/data/steady_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 6, P1-1: the shutter waits until the phone holds still.
void main() {
  final t0 = DateTime(2026, 11, 16);
  GyroSample at(int ms, double rate) => (x: rate, y: 0, z: 0, at: t0.add(Duration(milliseconds: ms)));

  test('steady once the rate stays under 0.15 rad/s for 150 ms', () async {
    final c = StreamController<GyroSample>();
    final wait = SteadyGate.wait(c.stream);
    // Still moving (the shutter tap), then settling.
    for (final (ms, rate) in [(0, 0.8), (20, 0.4), (40, 0.1), (100, 0.05), (160, 0.08), (200, 0.02)]) {
      c.add(at(ms, rate));
    }
    expect(await wait, isTrue);
    await c.close();
  });

  test('a twitch restarts the 150 ms', () async {
    final c = StreamController<GyroSample>();
    var done = false;
    final wait = SteadyGate.wait(c.stream).then((v) => done = v);
    for (final (ms, rate) in [(0, 0.05), (100, 0.05), (120, 0.3), (200, 0.05), (260, 0.05)]) {
      c.add(at(ms, rate));
    }
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse, reason: 'only 60 ms still since the twitch');
    c.add(at(360, 0.04));
    await wait;
    expect(done, isTrue);
    await c.close();
  });

  test('gives up after the timeout and shoots anyway', () async {
    final c = StreamController<GyroSample>();
    final wait = SteadyGate.wait(c.stream, timeout: const Duration(milliseconds: 50));
    c.add(at(0, 0.6));
    expect(await wait, isFalse);
    await c.close();
  });

  test('no gyroscope: no wait', () async {
    expect(await SteadyGate.wait(Stream<GyroSample>.error(UnsupportedError('none'))), isFalse);
  });
}
