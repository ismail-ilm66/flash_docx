import 'dart:io';

import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Round 6, P1-1: a document shot that is sharp on one side and smeared on
/// the other is flagged at ingest (the owner's pages 1 and 3).
void main() {
  late Directory tmp;
  setUpAll(() async => tmp = await Directory.systemTemp.createTemp('blurry'));
  tearDownAll(() => tmp.delete(recursive: true));

  const shot = CaptureMeta(sensorOrientation: 0, deviceTurns: 0);

  /// The letter page photo, its right half smeared like a turning phone.
  String photo(String name, {required bool shaken}) {
    final img = cv.imread('test/fixtures/edges/letter_page.jpg');
    if (shaken) {
      final x0 = img.cols ~/ 2;
      final roi = img.region(cv.Rect(x0, 0, img.cols - x0, img.rows));
      final smeared = cv.gaussianBlur(roi, (0, 0), 4);
      smeared.copyTo(roi);
      for (final m in [roi, smeared]) {
        m.dispose();
      }
    }
    final path = p.join(tmp.path, '$name.jpg');
    pipe.writeJpeg(img, path, quality: 92);
    img.dispose();
    return path;
  }

  IngestResult ingest(String src, {CaptureMeta? capture, double? aspect}) =>
      ingestInIsolate(IngestMsg(src, p.join(tmp.path, 'prev_${p.basename(src)}'), aspect, null, capture));

  test('a camera shot smeared on one side is flagged', () {
    final r = ingest(photo('shaken', shaken: true), capture: shot);
    expect(r.quad, isNotNull);
    expect(r.blurryCells, isNotEmpty);
    expect(r.blurryCells.every((c) => c.$2 >= 1), isTrue, reason: 'the right side: ${r.blurryCells}');
  });

  test('an evenly sharp shot is not', () {
    expect(ingest(photo('sharp', shaken: false), capture: shot).blurryCells, isEmpty);
  });

  test('imports and ID / passport shots are never checked', () {
    expect(ingest(photo('import', shaken: true)).blurryCells, isEmpty);
    expect(ingest(photo('card', shaken: true), capture: shot, aspect: 85.6 / 54).blurryCells, isEmpty);
  });
}
