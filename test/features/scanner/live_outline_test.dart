import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/live_outline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 11b, P0-15: the reference `LiveOutline`, with the fix list's
/// simulations (10 frames a second).
void main() {
  Quad page([double dx = 0, double dy = 0]) =>
      Quad(tl: Pt(0.2 + dx, 0.2 + dy), tr: Pt(0.8 + dx, 0.2 + dy), br: Pt(0.8 + dx, 0.8 + dy), bl: Pt(0.2 + dx, 0.8 + dy));

  /// Runs [frames] (quad, phone still) at 10 / s; the time of the capture.
  double? run(List<(Quad?, bool)> frames) {
    final o = LiveOutline(180, 320);
    for (final (i, (q, still)) in frames.indexed) {
      if (o.update(q, i / 10, phoneStill: still).capture) return i / 10;
    }
    return null;
  }

  test('shown after 2 frames with a page, hidden after 4 without', () {
    final o = LiveOutline(180, 320);
    expect(o.update(page(), 0).outline, isNull);
    expect(o.update(page(), 0.1).outline, isNotNull);
    for (var i = 0; i < 3; i++) {
      expect(o.update(null, 0.2 + i / 10).outline, isNotNull, reason: 'miss ${i + 1}');
    }
    expect(o.update(null, 0.5).outline, isNull);
  });

  test('steady hand: capture at about 0.9 s', () {
    final t = run([for (var i = 0; i < 30; i++) (page(), true)]);
    expect(t, inInclusiveRange(0.8, 1.0));
  });

  test('a small wobble pauses the timer, it does not restart it', () {
    final frames = [
      for (var i = 0; i < 5; i++) (page(), true),
      for (var i = 0; i < 2; i++) (page(0.03), true), // 2–5 %, short
      for (var i = 0; i < 20; i++) (page(), true),
    ];
    expect(run(frames), inInclusiveRange(0.8, 1.2));
  });

  test('a real move restarts it; the phone moving never captures', () {
    final moved = [
      for (var i = 0; i < 5; i++) (page(), true),
      for (var i = 0; i < 25; i++) (page(0.2), true),
    ];
    expect(run(moved), greaterThan(1.2));
    expect(run([for (var i = 0; i < 30; i++) (page(), false)]), isNull);
  });

  test('the same page is not taken twice', () {
    final o = LiveOutline(180, 320);
    var shots = 0;
    for (var i = 0; i < 60; i++) {
      if (o.update(page(), i / 10).capture) {
        shots++;
        o.shot();
      }
    }
    expect(shots, 1);
  });
}
