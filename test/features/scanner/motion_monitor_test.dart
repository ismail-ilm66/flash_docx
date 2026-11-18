import 'package:flash_dox/features/scanner/data/motion_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 7, P0-1: a hint while the phone moves; never a wait.
void main() {
  final t0 = DateTime(2026, 11, 18);
  GyroSample at(int ms, double rate) => (x: rate, y: 0, z: 0, at: t0.add(Duration(milliseconds: ms)));

  test('moving at 0.3 rad/s; still after 300 ms under 0.15', () {
    final m = MotionMonitor();
    expect(m.add(at(0, 0.1)), isFalse);
    expect(m.isMoving, isFalse);
    expect(m.add(at(20, 0.5)), isTrue);
    expect(m.isMoving, isTrue);
    for (final (ms, rate) in [(40, 0.1), (200, 0.2), (220, 0.05), (400, 0.05)]) {
      expect(m.add(at(ms, rate)), isFalse, reason: '$ms ms');
    }
    expect(m.isMoving, isTrue, reason: 'the 0.2 at 200 ms restarted the wait');
    expect(m.add(at(520, 0.05)), isTrue);
    expect(m.isMoving, isFalse);
  });

  test('a small tremor under 0.3 rad/s is not "moving"', () {
    final m = MotionMonitor();
    for (var ms = 0; ms < 1000; ms += 20) {
      m.add(at(ms, 0.25));
    }
    expect(m.isMoving, isFalse);
  });

  test('focus goes back to the page once after each move, never while moving', () {
    final m = MotionMonitor();
    expect(m.takeFocusRefresh(), isTrue, reason: 'first time');
    expect(m.takeFocusRefresh(), isFalse, reason: 'the phone has not moved');
    m.add(at(0, 0.6));
    expect(m.takeFocusRefresh(), isFalse, reason: 'still moving');
    m
      ..add(at(10, 0.01))
      ..add(at(400, 0.01));
    expect(m.takeFocusRefresh(), isTrue);
    expect(m.takeFocusRefresh(), isFalse);
  });
}
