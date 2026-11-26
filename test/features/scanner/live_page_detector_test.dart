import 'package:flash_dox/features/scanner/data/live_page_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 11, P1-7: the live outline's detection on a camera frame.
void main() {
  /// A sensor frame (landscape, as the back camera delivers it) with a
  /// bright page on a dark table; the page is at x 0.2–0.8, y 0.15–0.85 of
  /// the upright (portrait) picture.
  (Uint8List, int, int) frame() {
    const w = 320;
    const h = 180;
    final px = Uint8List(w * h)..fillRange(0, w * h, 40);
    // Upright (portrait) frame is h x w after a 90° clockwise turn: the
    // sensor's column x is the upright row, its row y the upright column
    // (from the right).
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final uprightX = (h - 1 - y) / h;
        final uprightY = x / w;
        if (uprightX > 0.2 && uprightX < 0.8 && uprightY > 0.15 && uprightY < 0.85) px[y * w + x] = 225;
      }
    }
    return (px, w, h);
  }

  test('a page in a sensor frame is found, upright', () {
    final (px, w, h) = frame();
    final q = detectFrame(px, w, h, 90);
    expect(q, isNotNull);
    // TL, TR, BR, BL of the upright page.
    final expected = [0.2, 0.15, 0.8, 0.15, 0.8, 0.85, 0.2, 0.85];
    for (var i = 0; i < 8; i++) {
      expect(q![i], closeTo(expected[i], 0.03), reason: 'value $i');
    }
  });

  test('an empty frame has no page', () {
    final px = Uint8List(320 * 180)..fillRange(0, 320 * 180, 40);
    expect(detectFrame(px, 320, 180, 90), isNull);
  });
}
