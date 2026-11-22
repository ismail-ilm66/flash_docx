import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Round 6, P0-2: each page is cleaned once and every filter, preview and
/// export starts from that.
void main() {
  late Directory tmp;
  late String photo;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('clean_base');
    // A 3000 × 4000 page in dim light: text lines on paper, plus sensor noise.
    final m = cv.Mat.fromScalar(4000, 3000, cv.MatType.CV_8UC3, cv.Scalar(200, 205, 210));
    for (var y = 500; y < 3500; y += 60) {
      cv.line(m, cv.Point(400, y), cv.Point(2600, y), cv.Scalar(40, 40, 40), thickness: 6);
    }
    final n = cv.Mat.zeros(4000, 3000, cv.MatType.CV_8UC3);
    cv.randn(n, cv.Scalar.all(0), cv.Scalar.all(6));
    final noisy = cv.add(m, n);
    photo = p.join(tmp.path, 'page.jpg');
    pipe.writeJpeg(noisy, photo, quality: 92);
    for (final x in [m, n, noisy]) {
      x.dispose();
    }
  });

  tearDownAll(() => tmp.delete(recursive: true));

  final edits = PageEdits(crop: Quad.full(inset: 0.05));

  // First: the process's peak memory only ever grows, so a big render
  // before this would hide what it measures.
  test('the 3000 px (High) base job on a 3000 × 4000 photo stays well under 600 MB', () {
    final before = ProcessInfo.maxRss;
    final out = p.join(tmp.path, 'mem_base.png');
    cleanBaseInIsolate(CleanBaseMsg(photo, edits, 3000, out, p.join(tmp.path, 'mem_prev.png')));
    final grew = (ProcessInfo.maxRss - before) / 1e6;
    // ignore: avoid_print
    print('3000 px cleaned base: +${grew.round()} MB peak');
    expect(grew, lessThan(600), reason: '+${grew.round()} MB');
  });

  group('each filter from a cleaned page equals the full filter', () {
    late cv.Mat warp;
    setUpAll(() {
      final img = pipe.readUpright(photo);
      warp = pipe.fitLongEdge(img, 1200);
      if (!identical(warp, img)) img.dispose();
    });
    tearDownAll(() => warp.dispose());

    int differing(cv.Mat a, cv.Mat b) {
      final d = cv.absDiff(a, b);
      final g = cv.cvtColor(d, cv.COLOR_BGR2GRAY);
      final n = cv.countNonZero(g);
      d.dispose();
      g.dispose();
      return n;
    }

    for (final f in [FilterType.auto, FilterType.colorBoost, FilterType.grayscale]) {
      test(f.name, () {
        final clean = pipe.cleanPage(warp);
        final a = pipe.applyFilterFromClean(clean, f);
        final b = pipe.applyFilter(warp, f);
        expect(differing(a, b), 0);
        for (final x in [clean, a, b]) {
          x.dispose();
        }
      });
    }

    test('idColor (card strength)', () {
      final clean = pipe.cleanPage(warp, card: true);
      final a = pipe.applyFilterFromClean(clean, FilterType.idColor);
      final b = pipe.idColorFilter(warp);
      expect(differing(a, b), 0);
      for (final x in [clean, a, b]) {
        x.dispose();
      }
    });
  });

  test('base → preview copy → Enhance look → export page, all from one clean-up', () {
    final base = p.join(tmp.path, 'base.png');
    final prev = p.join(tmp.path, 'prev.png');
    cleanBaseInIsolate(CleanBaseMsg(photo, edits, 2000, base, prev));
    final b = cv.imread(base);
    expect(math.max(b.cols, b.rows), 2000);
    b.dispose();
    final pv = cv.imread(prev);
    expect(math.max(pv.cols, pv.rows), 1200);
    pv.dispose();

    final look = p.join(tmp.path, 'look.jpg');
    lookFromCleanInIsolate(LookMsg(prev, edits, '', look, p.join(tmp.path, 'auto.png')));
    expect(File(look).existsSync(), isTrue);
    // Colour Boost reuses the Auto result cached by the Auto look.
    lookFromCleanInIsolate(LookMsg(prev, edits.copyWith(filter: FilterType.colorBoost), '', p.join(tmp.path, 'boost.jpg'), p.join(tmp.path, 'auto.png')));

    final page = p.join(tmp.path, 'page_out.jpg');
    fromCleanInIsolate(RenderMsg(base, edits.copyWith(brightness: 10), 2000, page, 85));
    final out = cv.imread(page);
    expect(math.max(out.cols, out.rows), 2000);
    out.dispose();

    final card = p.join(tmp.path, 'card.jpg');
    cardFromCleanInIsolate(CardMsg(base, edits.copyWith(filter: FilterType.idColor), 85.6, 54, 300, card));
    final c = cv.imread(card);
    expect((c.cols, c.rows), (1011, 638));
    c.dispose();
  });

  test('the instant image is cleaned and filtered, the same size as the look', () {
    final out = p.join(tmp.path, 'instant.jpg');
    instantLookInIsolate(LookMsg(photo, edits, p.join(tmp.path, 'work.jpg'), out));
    final m = cv.imread(out);
    expect(math.max(m.cols, m.rows), 1200);
    m.dispose();
  });
}
