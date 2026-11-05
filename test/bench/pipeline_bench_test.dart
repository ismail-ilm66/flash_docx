import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Host timings for the per-photo work, to compare before/after changes.
/// Run with: flutter test test/bench --tags bench
void main() {
  test('pipeline timings on a 12 MP photo', tags: ['bench'], () {
    final tmp = Directory.systemTemp.createTempSync('bench');
    final m = cv.Mat.fromScalar(3000, 4000, cv.MatType.CV_8UC3, cv.Scalar(60, 55, 50));
    final noise = cv.Mat.zeros(3000, 4000, cv.MatType.CV_8UC3);
    cv.randn(noise, cv.Scalar.all(0), cv.Scalar.all(12));
    cv.rectangle(m, cv.Rect(700, 400, 2600, 2200), cv.Scalar(235, 235, 235), thickness: -1);
    final img = cv.add(m, noise);
    final src = p.join(tmp.path, 'src.jpg');
    pipe.writeJpeg(img, src, quality: 92);
    for (final x in [m, noise, img]) {
      x.dispose();
    }
    final crop = Quad.full(inset: 0.15);

    int ms(void Function() f, {int runs = 3, void Function()? setUp}) {
      (setUp ?? f)(); // warm-up
      final sw = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        f();
      }
      return sw.elapsedMilliseconds ~/ runs;
    }

    final work = p.join(tmp.path, 'work.jpg');
    final results = <String, int>{
      'decode 12 MP': ms(() => pipe.readUpright(src).dispose()),
      'ingest (per capture/import)': ms(() => ingestInIsolate(IngestMsg(src, p.join(tmp.path, 'b.jpg'), null, null))),
      'enhance first preview (auto)': ms(() {
        File(work).deleteSync();
        lookInIsolate(LookMsg(src, PageEdits(crop: crop), work, p.join(tmp.path, 'l.jpg')));
      }, setUp: () => lookInIsolate(LookMsg(src, PageEdits(crop: crop), work, p.join(tmp.path, 'l.jpg')))),
      'enhance filter switch (b&w)': ms(() => lookInIsolate(LookMsg(src, PageEdits(crop: crop, filter: FilterType.bwPrint), work, p.join(tmp.path, 'w.jpg')))),
      'enhance filter switch (auto)': ms(() => lookInIsolate(LookMsg(src, PageEdits(crop: crop), work, p.join(tmp.path, 'a.jpg')))),
      'viewer caches (preview+thumb)': ms(() => cachesInIsolate(CachesMsg(src, PageEdits(crop: crop), p.join(tmp.path, 'p.jpg'), p.join(tmp.path, 't.jpg')))),
    };
    // ignore: avoid_print
    print(results.entries.map((e) => '${e.key.padRight(32)} ${e.value} ms').join('\n'));
    tmp.deleteSync(recursive: true);
  });
}
