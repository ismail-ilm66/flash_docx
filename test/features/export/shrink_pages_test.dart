import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// A synthetic A4 page at 2000 px: lines of small text and a colour photo
/// block, so JPEG size reacts to quality and size like a real scan.
String _page(Directory dir, int seed) {
  final rnd = math.Random(seed);
  final img = cv.Mat.fromScalar(2000, 1414, cv.MatType.CV_8UC3, cv.Scalar(240, 242, 244));
  const chars = 'abcdefghijklmnopqrstuvwxyz 0123456789';
  for (var y = 80; y < 1300; y += 34) {
    final line = String.fromCharCodes(List.generate(70, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    cv.putText(img, line, cv.Point(70, y), cv.FONT_HERSHEY_SIMPLEX, 0.75, cv.Scalar(30, 30, 30), thickness: 2);
  }
  final noise = cv.Mat.zeros(500, 1200, cv.MatType.CV_8UC3);
  cv.randu(noise, cv.Scalar(40, 90, 140), cv.Scalar(120, 200, 255));
  final photo = cv.gaussianBlur(noise, (9, 9), 0);
  photo.copyTo(img.region(cv.Rect(100, 1380, 1200, 500)));
  final path = p.join(dir.path, 'page_$seed.jpg');
  cv.imwrite(path, img, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 95]));
  for (final m in [img, noise, photo]) {
    m.dispose();
  }
  return path;
}

void main() {
  late Directory tmp;
  late List<String> bases;
  List<String> outputs() => [for (var i = 0; i < bases.length; i++) p.join(tmp.path, 'out', 'p$i.jpg')];
  int written(List<String> outs) => outs.fold(0, (s, o) => s + File(o).lengthSync());
  int longEdge(String path) {
    final m = cv.imread(path);
    final e = math.max(m.cols, m.rows);
    m.dispose();
    return e;
  }

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('shrink');
    bases = [_page(tmp, 1), _page(tmp, 2)];
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('a generous limit keeps 2000 px at quality 85', () {
    final outs = outputs();
    final r = shrinkInIsolate(ShrinkMsg(bases, 20 << 20, 3000, false, outs)) as ShrinkFits;
    expect(r.step, const ShrinkStep(2000, 85));
    expect(written(outs) + 3000, r.bytes);
    expect(longEdge(outs.first), 2000);
  });

  test('a tight limit shrinks until the pages fit, and the written files match', () {
    final outs = outputs();
    final best = shrinkInIsolate(ShrinkMsg(bases, 20 << 20, 3000, false, outputs())) as ShrinkFits;
    final target = best.bytes ~/ 3;
    final r = shrinkInIsolate(ShrinkMsg(bases, target, 3000, false, outs)) as ShrinkFits;
    expect(r.bytes, lessThanOrEqualTo(target));
    expect(written(outs) + 3000, r.bytes, reason: 'measured in memory = written to disk');
    expect(longEdge(outs.first), r.step.longEdge);
    expect(r.step, isNot(const ShrinkStep(2000, 85)));
  });

  test('a tiny limit asks for black and white, then gives up', () {
    final colour = shrinkInIsolate(ShrinkMsg(bases, 20000, 3000, false, outputs()));
    expect(colour, isA<ShrinkNeedsGrayscale>());
    final gray = shrinkInIsolate(ShrinkMsg(bases, 20000, 3000, true, outputs()));
    expect(gray, isA<ShrinkCantFit>());
  });

  test('black and white fits where colour could not', () {
    final colourFloor = (shrinkInIsolate(ShrinkMsg(bases, 1, 0, false, outputs())) as ShrinkNeedsGrayscale).smallestBytes;
    final grayFloor = (shrinkInIsolate(ShrinkMsg(bases, 1, 0, true, outputs())) as ShrinkCantFit).smallestBytes;
    expect(grayFloor, lessThan(colourFloor));
    final target = (grayFloor + colourFloor) ~/ 2;
    expect(shrinkInIsolate(ShrinkMsg(bases, target, 0, false, outputs())), isA<ShrinkNeedsGrayscale>());
    final outs = outputs();
    final r = shrinkInIsolate(ShrinkMsg(bases, target, 0, true, outs)) as ShrinkFits;
    expect(r.step.grayscale, isTrue);
    final m = cv.imread(outs.first, flags: cv.IMREAD_UNCHANGED);
    expect(m.channels, 1, reason: 'written as a grayscale JPEG');
    m.dispose();
  });
}
