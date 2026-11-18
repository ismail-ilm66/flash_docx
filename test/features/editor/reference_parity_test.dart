import 'dart:convert';
import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// The Dart pipeline must reproduce the owner's Python reference
/// (tool/reference/flashdox_reference.py). Reference outputs are produced by
/// `python3 tool/reference/dump_reference.py` into test/fixtures/reference/.
///
/// Filters are compared on the reference's own warp, so only the filter code
/// is under test. Measured on the two owner photos and a plain letter page
/// (round 5): mean |Δ| ≤ 0.16 levels, p99 ≤ 3 (OCR and B&W print identical).
/// Limits leave a little headroom; the round 5 plan asks for mean ≤ 3.
void main() {
  final refDir = Directory('test/fixtures/reference');
  final names = refDir.existsSync()
      ? refDir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => n.endsWith('_warp.png'))
          .map((n) => n.replaceAll('_warp.png', ''))
          .toList()
      : <String>[];

  ({double mean, double p99}) absDiff(cv.Mat a, cv.Mat b) {
    expect(a.rows, b.rows);
    expect(a.cols, b.cols);
    final d = cv.absDiff(a, b);
    final flat = d.data;
    final hist = List<int>.filled(256, 0);
    var sum = 0;
    for (final v in flat) {
      hist[v]++;
      sum += v;
    }
    var acc = 0;
    var p99 = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= flat.length * 0.99) {
        p99 = v;
        break;
      }
    }
    d.dispose();
    return (mean: sum / flat.length, p99: p99.toDouble());
  }

  for (final name in names) {
    group(name, () {
      late cv.Mat warp;
      setUpAll(() => warp = cv.imread(p.join(refDir.path, '${name}_warp.png')));
      tearDownAll(() => warp.dispose());

      cv.Mat ref(String suffix, {int flags = cv.IMREAD_COLOR}) =>
          cv.imread(p.join(refDir.path, '${name}_$suffix.png'), flags: flags);

      final cases = <String, (cv.Mat Function(cv.Mat), int)>{
        'auto': (pipe.autoFilter, cv.IMREAD_COLOR),
        'id': (pipe.idColorFilter, cv.IMREAD_COLOR),
        'bw': (pipe.bwPrintFilter, cv.IMREAD_COLOR),
        'ocr': (pipe.ocrImage, cv.IMREAD_GRAYSCALE),
        'dnprev': (pipe.denoisePreview, cv.IMREAD_COLOR),
      };
      for (final MapEntry(key: suffix, value: (fn, flags)) in cases.entries) {
        test('$suffix filter matches the reference', () {
          final expected = ref(suffix, flags: flags);
          final got = fn(warp);
          final d = absDiff(got, expected);
          // ignore: avoid_print
          print('$name $suffix: mean |Δ| ${d.mean.toStringAsFixed(2)}, p99 ${d.p99}');
          if (suffix == 'bw') {
            // Binary output: a pixel either matches or flips; allow ≤ 0.1 % flips.
            expect(d.mean / 255, lessThan(0.001));
          } else {
            expect(d.mean, lessThan(0.3));
            expect(d.p99, lessThanOrEqualTo(3));
          }
          got.dispose();
          expected.dispose();
        });
      }

      test('on a noisy copy, the fast denoise path matches too (round 6)', () {
        final noisy = cv.imread(p.join(refDir.path, '${name}_noisy.png'));
        expect(pipe.estimateNoise(noisy), greaterThan(1.5));
        for (final (suffix, fn) in [('auto', pipe.autoFilter), ('id', pipe.idColorFilter)]) {
          final expected = ref('noisy_$suffix');
          final got = fn(noisy);
          final d = absDiff(got, expected);
          // ignore: avoid_print
          print('$name noisy $suffix: mean |Δ| ${d.mean.toStringAsFixed(2)}, p99 ${d.p99}');
          expect(d.mean, lessThan(0.3), reason: suffix);
          expect(d.p99, lessThanOrEqualTo(3), reason: suffix);
          got.dispose();
          expected.dispose();
        }
        noisy.dispose();
      });

      test('blurry regions match the reference (round 6, P1-1)', () {
        final expected = jsonDecode(File(p.join(refDir.path, '${name}_blur.json')).readAsStringSync()) as Map<String, dynamic>;
        List<List<int>> cells(List<(int, int)> c) => [for (final (r, k) in c) [r, k]];
        // The fixtures come from the round 6 reference (any cell under
        // 0.5 × the best). TODO(round 7): regenerate from the round 7
        // reference (2 cells under 0.4) when it arrives.
        expect(cells(pipe.blurryRegions(warp, ratio: 0.5, minCells: 1)), expected['warp']);
        final shaken = cv.imread(p.join(refDir.path, '${name}_shaken.png'));
        expect(cells(pipe.blurryRegions(shaken, ratio: 0.5, minCells: 1)), expected['shaken']);
        shaken.dispose();
      });

      test('every candidate map matches the reference (P0-4)', () {
        final small = cv.imread(p.join(refDir.path, '${name}_small.png'));
        final maps = pipe.candidateMaps(small);
        expect(maps.map((m) => m.$1), ['smooth', 'edges', 'bright', 'lowsat', 'smooth+lowsat', 'smooth+bright']);
        for (final (mapName, got) in maps) {
          final expected = cv.imread(p.join(refDir.path, '${name}_map_${mapName.replaceAll('+', '_')}.png'), flags: cv.IMREAD_GRAYSCALE);
          final diff = cv.absDiff(got, expected);
          final differing = cv.countNonZero(diff) / (diff.rows * diff.cols);
          // ignore: avoid_print
          print('$name map $mapName: ${(differing * 100).toStringAsFixed(2)} % pixels differ');
          expect(differing, lessThan(0.001), reason: mapName);
          for (final m in [got, expected, diff]) {
            m.dispose();
          }
        }
        small.dispose();
      });

      test('detection matches the reference corners', () {
        final meta = jsonDecode(File('test/fixtures/edges/$name.json').readAsStringSync()) as Map<String, dynamic>;
        final refCorners = (meta['reference_found'] ?? meta) as Map<String, dynamic>;
        final img = cv.imread('test/fixtures/edges/$name.jpg');
        final r = pipe.detectDocument(img, aspectHint: (meta['aspect'] as num?)?.toDouble());
        img.dispose();
        expect(r.found, isTrue, reason: '$r');
        final got = r.quad!.points;
        for (final (i, k) in ['tl', 'tr', 'br', 'bl'].indexed) {
          final e = refCorners[k] as List;
          expect(got[i].x, closeTo((e[0] as num).toDouble(), 0.01), reason: '$k x');
          expect(got[i].y, closeTo((e[1] as num).toDouble(), 0.01), reason: '$k y');
        }
        expect(r.strategy, meta['map']);
      });
    });
  }

  test('warp forces the card shape like the reference', () {
    final img = cv.Mat.fromScalar(600, 800, cv.MatType.CV_8UC3, cv.Scalar.all(128));
    final q = Quad.full(inset: 0.1);
    final out = pipe.warpToQuad(img, q, aspect: CardAspect.id1);
    expect(out.cols / out.rows, closeTo(CardAspect.id1, 0.01));
    out.dispose();
    img.dispose();
  });

  test('P0-2: Auto leaves plain paper white, no grey marble', () {
    final warp = cv.imread(p.join(refDir.path, 'letter_page_warp.png'));
    final out = pipe.autoFilter(warp);
    final gray = cv.cvtColor(out, cv.COLOR_BGR2GRAY);
    var paper = 0;
    var band = 0;
    for (final v in gray.data) {
      if (v > 200) paper++;
      if (v > 200 && v < 250) band++;
    }
    // Before the float rewrite 95 % of the paper sat in this grey band.
    expect(band / paper, lessThan(0.03));
    for (final m in [warp, out, gray]) {
      m.dispose();
    }
  });
}

abstract final class CardAspect {
  static const double id1 = 85.6 / 54;
}
