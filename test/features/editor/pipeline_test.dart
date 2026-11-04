import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Draws a bright, slightly rotated "page" with a few dark text lines on a
/// dark background and saves it as JPEG. Returns the path and the expected
/// normalised corners.
(String, Quad) makeSample(Directory dir, {int w = 1200, int h = 1600}) {
  final img = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar(60, 55, 50));
  final corners = [
    cv.Point((w * 0.22).round(), (h * 0.18).round()),
    cv.Point((w * 0.80).round(), (h * 0.22).round()),
    cv.Point((w * 0.78).round(), (h * 0.84).round()),
    cv.Point((w * 0.18).round(), (h * 0.80).round()),
  ];
  final poly = cv.VecPoint.fromList(corners);
  cv.fillPoly(img, cv.VecVecPoint.fromList([corners]), cv.Scalar(235, 238, 240));
  poly.dispose();
  // Text-like lines.
  for (var i = 0; i < 12; i++) {
    final y = (h * 0.30 + i * h * 0.04).round();
    cv.line(img, cv.Point((w * 0.30).round(), y), cv.Point((w * 0.68).round(), y), cv.Scalar(30, 30, 30), thickness: 4);
  }
  final path = p.join(dir.path, 'sample.jpg');
  pipe.writeJpeg(img, path, quality: 92);
  img.dispose();
  final quad = Quad.fromUnordered([
    for (final c in corners) Pt(c.x / w, c.y / h),
  ]);
  return (path, quad);
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('flashdox_pipe');
  });

  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  test('detects the page corners within 2% of each edge', () {
    final (path, expected) = makeSample(tmp);
    final img = pipe.readUpright(path);
    final quad = pipe.detectDocumentQuad(img);
    img.dispose();
    expect(quad, isNotNull);
    final got = quad!.points;
    final exp = expected.points;
    for (var i = 0; i < 4; i++) {
      expect(got[i].x, closeTo(exp[i].x, 0.02), reason: 'corner $i x');
      expect(got[i].y, closeTo(exp[i].y, 0.02), reason: 'corner $i y');
    }
  });

  test('returns null on a flat image', () {
    final flat = cv.Mat.fromScalar(800, 600, cv.MatType.CV_8UC3, cv.Scalar(200, 200, 200));
    expect(pipe.detectDocumentQuad(flat), isNull);
    flat.dispose();
  });

  test('render warps, rotates, filters and respects the long edge cap', () {
    final (path, quad) = makeSample(tmp);
    for (final filter in FilterType.values) {
      final out = pipe.renderEdits(
        path,
        PageEdits(crop: quad, quarterTurns: 1, filter: filter),
        maxLongEdge: RenderPx.previewLongEdge,
      );
      expect(out.isEmpty, isFalse, reason: '$filter');
      // After a 90° turn the page (taller than wide) becomes landscape.
      expect(out.cols, greaterThan(out.rows), reason: '$filter');
      expect(out.cols, lessThanOrEqualTo(RenderPx.previewLongEdge));
      expect(out.channels, 3);
      out.dispose();
    }
  });

  test('B&W print output is mostly pure black or white', () {
    final (path, quad) = makeSample(tmp);
    final out = pipe.renderEdits(path, PageEdits(crop: quad, filter: FilterType.bwPrint), maxLongEdge: 600);
    final gray = cv.cvtColor(out, cv.COLOR_BGR2GRAY);
    final (_, white) = cv.threshold(gray, 200, 255, cv.THRESH_BINARY);
    final (_, black) = cv.threshold(gray, 55, 255, cv.THRESH_BINARY_INV);
    final total = gray.rows * gray.cols;
    final extreme = (cv.countNonZero(white) + cv.countNonZero(black)) / total;
    expect(extreme, greaterThan(0.95));
    for (final m in [out, gray, white, black]) {
      m.dispose();
    }
  });

  test('snapQuadToAspect keeps the centre and fixes the ratio', () {
    final q = Quad.fromUnordered(const [Pt(0.2, 0.3), Pt(0.8, 0.3), Pt(0.8, 0.6), Pt(0.2, 0.6)]);
    final snapped = pipe.snapQuadToAspect(q, 85.6 / 54, imageAspect: 1);
    expect(snapped.avgWidth / snapped.avgHeight, closeTo(85.6 / 54, 0.01));
    final cx = snapped.points.map((p) => p.x).reduce((a, b) => a + b) / 4;
    final cy = snapped.points.map((p) => p.y).reduce((a, b) => a + b) / 4;
    expect(cx, closeTo(0.5, 1e-6));
    expect(cy, closeTo(0.45, 1e-6));
  });

  test('writeJpeg/readUpright round-trip and png by extension', () {
    final m = cv.Mat.fromScalar(10, 20, cv.MatType.CV_8UC3, cv.Scalar(1, 2, 3));
    final png = p.join(tmp.path, 'x.png');
    pipe.writeJpeg(m, png);
    final back = pipe.readUpright(png);
    expect(back.cols, 20);
    expect(back.rows, 10);
    expect(File(png).readAsBytesSync().sublist(1, 4), [0x50, 0x4E, 0x47]);
    m.dispose();
    back.dispose();
  });
}
