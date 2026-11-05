import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Writes docs/round3/results_dart.jpg — the Dart pipeline on the owner's
/// photos, laid out like the reference's results_documents.jpg — and prints
/// timings for a full-resolution 16 MP export.
/// Run: flutter test test/bench --tags bench --run-skipped
void main() {
  test('evidence sheet + 16 MP export timings', tags: ['bench'], () {
    cv.Mat fit(cv.Mat m, int h) {
      final out = cv.resize(m, ((m.cols * h / m.rows).round(), h), interpolation: cv.INTER_AREA);
      return out;
    }

    cv.Mat label(cv.Mat m, String text) {
      final out = m.clone();
      cv.rectangle(out, cv.Rect(0, 0, out.cols, 34), cv.Scalar.all(0), thickness: -1);
      cv.putText(out, text, cv.Point(8, 24), cv.FONT_HERSHEY_SIMPLEX, 0.7, cv.Scalar.all(255), thickness: 2);
      return out;
    }

    cv.Mat pad(cv.Mat m) => cv.copyMakeBorder(m, 6, 6, 6, 6, cv.BORDER_CONSTANT, value: cv.Scalar.all(255));

    final rows = <cv.Mat>[];
    final photos = Directory('test/fixtures/edges').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in photos) {
      final name = p.basenameWithoutExtension(f.path);
      final img = pipe.readUpright(f.path);
      final r = pipe.detectDocument(img);
      final q = r.quad ?? Quad.full(inset: 0.05);
      final vis = img.clone();
      final poly = cv.VecVecPoint.fromList([
        [for (final pt in q.points) cv.Point((pt.x * img.cols).round(), (pt.y * img.rows).round())],
      ]);
      cv.polylines(vis, poly, true, r.found ? cv.Scalar(0, 220, 0) : cv.Scalar(0, 0, 255), thickness: 4);
      final warp = pipe.warpToQuad(img, q);
      final tiles = [
        label(fit(vis, 420), '$name: ${r.found ? 'found' : 'NOT found'} (${r.strategy})'),
        label(fit(warp, 420), 'Original (crop only)'),
        label(fit(pipe.autoFilter(warp), 420), 'Auto (colour)'),
        label(fit(pipe.idColorFilter(warp), 420), 'ID colour'),
        label(fit(pipe.bwPrintFilter(warp), 420), 'B&W print'),
      ].map(pad).toList();
      var row = tiles.first.clone();
      for (final t in tiles.skip(1)) {
        final next = cv.hconcat(row, t);
        row.dispose();
        row = next;
      }
      rows.add(row);
      poly.dispose();
      for (final m in [img, vis, warp, ...tiles]) {
        m.dispose();
      }
    }
    final width = rows.map((r) => r.cols).reduce((a, b) => a > b ? a : b);
    final padded = [
      for (final r in rows) cv.copyMakeBorder(r, 0, 0, 0, width - r.cols, cv.BORDER_CONSTANT, value: cv.Scalar.all(255)),
    ];
    var sheet = padded.first.clone();
    for (final r in padded.skip(1)) {
      final next = cv.vconcat(sheet, r);
      sheet.dispose();
      sheet = next;
    }
    pipe.writeJpeg(sheet, 'docs/round3/results_dart.jpg', quality: 88);

    // 16 MP (4608 × 3456, the Mate 10 Lite's sensor) full-resolution exports.
    final tmp = Directory.systemTemp.createTempSync('ev');
    final big = cv.Mat.fromScalar(3456, 4608, cv.MatType.CV_8UC3, cv.Scalar(200, 205, 210));
    final noise = cv.Mat.zeros(3456, 4608, cv.MatType.CV_8UC3);
    cv.randn(noise, cv.Scalar.all(0), cv.Scalar.all(10));
    final noisy = cv.add(big, noise);
    final src = p.join(tmp.path, 'p16.jpg');
    pipe.writeJpeg(noisy, src, quality: 92);
    for (final m in [big, noise, noisy]) {
      m.dispose();
    }
    const crop = Quad(tl: Pt(0.08, 0.06), tr: Pt(0.92, 0.07), br: Pt(0.93, 0.94), bl: Pt(0.07, 0.93));
    final timings = <String, int>{};
    for (final (label, edits, cap) in [
      ('High (full res), Auto', const PageEdits(crop: crop), null),
      ('High (full res), ID colour', const PageEdits(crop: crop, filter: FilterType.idColor), null),
      ('High (full res), B&W print', const PageEdits(crop: crop, filter: FilterType.bwPrint), null),
      ('Standard (2000 px), Auto', const PageEdits(crop: crop), 2000),
      ('Preview (1200 px), Auto', const PageEdits(crop: crop), 1200),
    ]) {
      final sw = Stopwatch()..start();
      pipe.renderEdits(src, edits, maxLongEdge: cap).dispose();
      timings[label] = sw.elapsedMilliseconds;
    }
    tmp.deleteSync(recursive: true);
    // ignore: avoid_print
    print(timings.entries.map((e) => '${e.key.padRight(30)} ${e.value} ms').join('\n'));
    for (final m in [sheet, ...rows, ...padded]) {
      m.dispose();
    }
  });
}
