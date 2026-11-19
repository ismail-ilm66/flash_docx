import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Round 8, P0-7: dark slivers of table along a curled page's sides print
/// as black lines. They go; page content at the edge stays.
void main() {
  const w = 1400;
  const h = 2000;
  final white = cv.Scalar(250, 250, 250);
  final ink = cv.Scalar(30, 30, 30);
  final table = cv.Scalar(60, 75, 95);

  cv.Mat page() {
    final m = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, white);
    // Lines of text, starting near the left margin but not touching it.
    for (var y = 300; y < 1700; y += 50) {
      cv.rectangle(m, cv.Rect(60, y, 1200, 12), ink, thickness: -1);
    }
    return m;
  }

  /// Mean gray level of a rectangle.
  double level(cv.Mat m, cv.Rect r) {
    final roi = m.region(r);
    final g = cv.cvtColor(roi, cv.COLOR_BGR2GRAY);
    final v = cv.mean(g).val1;
    roi.dispose();
    g.dispose();
    return v;
  }

  test('a dark wedge and a thin frame of table are painted paper-white', () {
    final m = page();
    // A wedge down the left side (a curled edge), 0 → 4 % wide.
    final wedge = cv.VecPoint.fromList([cv.Point(0, 0), cv.Point(56, 0), cv.Point(0, h - 1)]);
    cv.fillPoly(m, cv.VecVecPoint.fromList([wedge.toList()]), table);
    // A 1.5 % strip all around (the crop sat just outside the paper).
    cv.rectangle(m, cv.Rect(0, 0, w, h), table, thickness: 40);
    final out = pipe.cleanPageBorder(m);
    for (final r in [cv.Rect(0, 0, 20, h), cv.Rect(0, 0, w, 15), cv.Rect(w - 15, 0, 15, h), cv.Rect(0, h - 15, w, 15), cv.Rect(0, 10, 50, 40)]) {
      expect(level(out, r), greaterThan(245), reason: '$r');
    }
    expect(level(out, cv.Rect(60, 300, 1200, 12)), lessThan(40), reason: 'the text is untouched');
    m.dispose();
    out.dispose();
  });

  test('a black header bar and a photo printed to the edge stay', () {
    final m = page();
    cv.rectangle(m, cv.Rect(0, 0, w, 180), ink, thickness: -1); // 9 % deep
    cv.rectangle(m, cv.Rect(w - 400, 900, 400, 500), cv.Scalar(90, 60, 40), thickness: -1);
    final out = pipe.cleanPageBorder(m);
    expect(level(out, cv.Rect(0, 0, w, 180)), lessThan(40));
    expect(level(out, cv.Rect(w - 400, 900, 400, 500)), lessThan(90));
    m.dispose();
    out.dispose();
  });

  test('not on ID cards, passport photos or the Original filter', () {
    final m = cv.Mat.fromScalar(100, 100, cv.MatType.CV_8UC3, white);
    for (final e in [
      const PageEdits(outputAspect: 85.6 / 54),
      const PageEdits(photoWidthMm: 35, photoHeightMm: 45),
      const PageEdits(filter: FilterType.original),
    ]) {
      final copy = m.clone();
      expect(identical(pipe.withCleanBorder(copy, e), copy), isTrue, reason: '$e');
      copy.dispose();
    }
    m.dispose();
  });

  test('fast enough to run on every page', () {
    final m = page();
    cv.rectangle(m, cv.Rect(0, 0, w, h), table, thickness: 40);
    pipe.cleanPageBorder(m).dispose(); // warm-up
    final sw = Stopwatch()..start();
    pipe.cleanPageBorder(m).dispose();
    // ignore: avoid_print
    print('cleanPageBorder 1400×2000: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(300), reason: 'JIT on the Mac; the phone build is AOT');
    m.dispose();
  });
}
