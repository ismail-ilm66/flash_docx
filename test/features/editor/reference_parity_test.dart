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
/// is under test. Measured on the two owner photos: mean |Δ| ≤ 0.18 levels, p99 ≤ 3
/// (OCR and B&W print identical). Limits leave a little headroom.
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
}

abstract final class CardAspect {
  static const double id1 = 85.6 / 54;
}
