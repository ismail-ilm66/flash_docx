import 'package:flash_dox/features/scanner/data/live_page_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 11b, P0-15: `detect_live` on a small BGR camera frame.
void main() {
  /// A sensor frame (landscape, as the back camera delivers it) with a
  /// bright page on a dark table; the page is at x 0.2–0.8, y 0.15–0.85 of
  /// the upright (portrait) picture.
  (Uint8List, int, int) frame() {
    const w = 320;
    const h = 180;
    final px = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 40);
    // Upright (portrait) frame is h x w after a 90° clockwise turn: the
    // sensor's column x is the upright row, its row y the upright column
    // (from the right).
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final uprightX = (h - 1 - y) / h;
        final uprightY = x / w;
        if (uprightX > 0.2 && uprightX < 0.8 && uprightY > 0.15 && uprightY < 0.85) px.fillRange((y * w + x) * 3, (y * w + x) * 3 + 3, 225);
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

  test('a frame with only table (dark, coloured) has no page', () {
    final px = Uint8List(320 * 180 * 3);
    for (var i = 0; i < px.length; i += 3) {
      px
        ..[i] = 30
        ..[i + 1] = 60
        ..[i + 2] = 120;
    }
    expect(detectFrame(px, 320, 180, 90), isNull);
  });
}
