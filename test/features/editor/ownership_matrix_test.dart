import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Every combination of crop / rotation / size cap goes through each render
/// entry point. A double free aborts the test process, so simply finishing
/// this file is the assertion that native memory is released exactly once.
void main() {
  late Directory tmp;
  late String photo;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('flashdox_own');
    // Larger than every cap below, like a real 12 MP capture scaled down.
    final m = cv.Mat.fromScalar(2400, 1800, cv.MatType.CV_8UC3, cv.Scalar(200, 190, 180));
    photo = p.join(tmp.path, 'photo.jpg');
    pipe.writeJpeg(m, photo);
    m.dispose();
  });

  tearDownAll(() => tmp.delete(recursive: true));

  final crops = <String, Quad?>{
    'no crop': null,
    'full crop': Quad.full(),
    'inset crop': Quad.full(inset: 0.2),
  };
  const caps = <int?>[null, 400, 1600, 5000];

  for (final crop in crops.entries) {
    for (var turns = 0; turns < 4; turns++) {
      for (final cap in caps) {
        final edits = PageEdits(crop: crop.value, quarterTurns: turns);
        final label = '${crop.key}, $turns turns, cap $cap';

        test('renderEdits: $label', () {
          final out = pipe.renderEdits(photo, edits, maxLongEdge: cap);
          if (cap != null) expect(math.max(out.cols, out.rows), lessThanOrEqualTo(cap));
          out.dispose();
        });

        test("cropAndRotate keeps the caller's Mat alive: $label", () {
          final src = pipe.readUpright(photo);
          final out = pipe.cropAndRotate(src, edits, maxLongEdge: cap);
          // src must still be usable whatever cropAndRotate did.
          expect(src.cols, 1800);
          expect(src.rows, 2400);
          pipe.disposeUnless(out, src);
          src.dispose();
        });
      }
    }
    test('renderForOcr: ${crop.key}', () {
      for (var turns = 0; turns < 4; turns++) {
        pipe.renderForOcr(photo, PageEdits(crop: crop.value, quarterTurns: turns)).dispose();
      }
    });
  }
}
