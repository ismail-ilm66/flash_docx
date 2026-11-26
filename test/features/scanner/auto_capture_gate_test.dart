import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/auto_capture_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 11, P1-8: auto capture.
void main() {
  final page = Quad.full(inset: 0.1);
  Quad shifted(double d) => Quad.full(inset: 0.1 + d);
  final t0 = DateTime(2026, 11, 26, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('takes one photo after 0.8 s of a steady page and a still phone', () {
    final g = AutoCaptureGate();
    expect(g.update(page, moving: false, now: at(0)), isFalse);
    for (var ms = 200; ms < 800; ms += 200) {
      expect(g.update(page, moving: false, now: at(ms)), isFalse, reason: '$ms ms');
      expect(g.progress, closeTo(ms / 800, 0.01));
    }
    expect(g.update(page, moving: false, now: at(800)), isTrue);
    // The same page again: never a second shot.
    for (var ms = 1200; ms < 4000; ms += 200) {
      expect(g.update(page, moving: false, now: at(ms)), isFalse);
    }
  });

  test('the ring resets when the phone or the page moves', () {
    final g = AutoCaptureGate()..update(page, moving: false, now: at(0));
    g.update(page, moving: false, now: at(200));
    g.update(page, moving: false, now: at(600));
    expect(g.progress, greaterThan(0.4));
    g.update(page, moving: true, now: at(700));
    expect(g.progress, 0);
    g
      ..update(page, moving: false, now: at(800))
      ..update(shifted(0.05), moving: false, now: at(1000));
    expect(g.progress, 0, reason: 'corners moved more than 2 %');
  });

  test('after a shot, a new page (or none in between) is taken again', () {
    final g = AutoCaptureGate()..update(page, moving: false, now: at(0));
    for (var ms = 200; ms <= 1000; ms += 200) {
      g.update(page, moving: false, now: at(ms));
    }
    g.update(null, moving: false, now: at(1200)); // the page was swapped
    var shots = 0;
    for (var ms = 1400; ms <= 2600; ms += 200) {
      if (g.update(page, moving: false, now: at(ms))) shots++;
    }
    expect(shots, 1);
  });
}
