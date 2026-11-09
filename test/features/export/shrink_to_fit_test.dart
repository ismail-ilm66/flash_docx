import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic pages: bytes grow with pixels and quality; grayscale is 40 %
/// smaller.
int Function(ShrinkStep) pages(int count, {double perMegapixel = 300000}) => (s) {
      final mp = (s.longEdge * s.longEdge * 0.707) / 1e6;
      final q = 0.25 + (s.quality - 55) / 30 * 0.75; // 0.25 at q55 … 1.0 at q85
      return (count * mp * perMegapixel * q * (s.grayscale ? 0.6 : 1)).round() + 2000;
    };

void main() {
  test('edges: 2000 down by 15 % to a 1100 floor', () {
    expect(ShrinkToFit.edges, [2000, 1700, 1445, 1228, 1100]);
  });

  test('a passport photo may go down to 240 px', () {
    final edges = ShrinkToFit.edgesDownTo(ShrinkToFit.photoMinEdge);
    expect(edges.first, 2000);
    expect(edges.last, 240);
    final m = pages(1);
    final target = m(const ShrinkStep(300, 70)) + 10;
    expect(ShrinkToFit.search(target, m), isA<ShrinkNeedsGrayscale>(), reason: 'pages stop at 1100 px');
    final r = ShrinkToFit.search(target, m, min: ShrinkToFit.photoMinEdge) as ShrinkFits;
    expect(r.step.longEdge, lessThan(ShrinkToFit.minEdge), reason: "below the pages' floor");
    expect(r.bytes, lessThanOrEqualTo(target));
  });

  ShrinkOutcome run(int target, int Function(ShrinkStep) m, {bool grayscale = false}) {
    final fast = ShrinkToFit.search(target, m, grayscale: grayscale);
    // Same answer as trying every step in order.
    final slow = ShrinkToFit.steps(grayscale: grayscale).where((s) => m(s) <= target).firstOrNull;
    if (fast is ShrinkFits) {
      expect(fast.step, slow);
    } else {
      expect(slow, isNull);
    }
    return fast;
  }

  test('fits at the first try', () {
    final r = run(10 << 20, pages(3));
    expect(r, isA<ShrinkFits>());
    expect((r as ShrinkFits).step, const ShrinkStep(2000, 85));
    expect(r.step.hardToRead, isFalse);
  });

  test('fits after a quality step', () {
    final m = pages(3);
    final target = m(const ShrinkStep(2000, 75)) + 10;
    final r = run(target, m) as ShrinkFits;
    expect(r.step, const ShrinkStep(2000, 75));
    expect(r.bytes, lessThanOrEqualTo(target));
  });

  test('fits after a resize', () {
    final m = pages(3);
    final target = m(const ShrinkStep(2000, 55)) - 1;
    final r = run(target, m) as ShrinkFits;
    expect(r.step.longEdge, 1700, reason: 'nothing at 2000 px fits');
  });

  test('small results are flagged hard to read', () {
    final m = pages(3);
    final r = run(m(const ShrinkStep(1445, 55)) - 1, m) as ShrinkFits;
    expect(r.step.longEdge, 1228);
    expect(r.step.hardToRead, isTrue, reason: 'under 1400 px');
  });

  test('needs grayscale when colour cannot fit, then fits in grayscale', () {
    final m = pages(3);
    final target = (m(const ShrinkStep(1100, 55)) * 0.8).round();
    final colour = run(target, m);
    expect(colour, isA<ShrinkNeedsGrayscale>());
    expect((colour as ShrinkNeedsGrayscale).smallestBytes, m(const ShrinkStep(1100, 55)));
    final gray = run(target, m, grayscale: true);
    expect(gray, isA<ShrinkFits>());
    expect((gray as ShrinkFits).step.grayscale, isTrue);
  });

  test("can't fit even in grayscale", () {
    final r = run(3000, pages(20), grayscale: true);
    expect(r, isA<ShrinkCantFit>());
  });

  test('measures far fewer than every step', () {
    var calls = 0;
    final m = pages(3);
    ShrinkToFit.search(m(const ShrinkStep(1228, 60)), (s) {
      calls++;
      return m(s);
    });
    expect(calls, lessThan(14));
  });
}
