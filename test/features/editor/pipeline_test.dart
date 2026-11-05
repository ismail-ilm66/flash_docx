import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Draws a synthetic "photo": a page or card on a background, optionally
/// tilted, with text-like lines, noise and a brightness gradient (shadow).
(String, Quad) makeSample(
  Directory dir, {
  required String name,
  int w = 1200,
  int h = 1600,
  cv.Scalar? bg,
  cv.Scalar? page,
  double tiltDeg = 4,
  double scale = 0.6,
  bool rounded = false,
  bool shadow = true,
  double noise = 6,
  bool lowLight = false,
}) {
  final bgColor = bg ?? cv.Scalar(60, 55, 50);
  final pageColor = page ?? cv.Scalar(235, 238, 240);
  final img = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, bgColor);

  // Rotated rectangle for the page.
  final cx = w / 2;
  final cy = h / 2;
  final pw = w * scale;
  final ph = pw * 1.3;
  final a = tiltDeg * math.pi / 180;
  cv.Point rot(double dx, double dy) => cv.Point(
        (cx + dx * math.cos(a) - dy * math.sin(a)).round(),
        (cy + dx * math.sin(a) + dy * math.cos(a)).round(),
      );
  final corners = [rot(-pw / 2, -ph / 2), rot(pw / 2, -ph / 2), rot(pw / 2, ph / 2), rot(-pw / 2, ph / 2)];
  if (rounded) {
    // Approximate rounded corners by drawing the polygon then filling circles.
    cv.fillPoly(img, cv.VecVecPoint.fromList([corners]), pageColor);
    for (final c in corners) {
      cv.circle(img, c, 18, pageColor, thickness: -1);
    }
  } else {
    cv.fillPoly(img, cv.VecVecPoint.fromList([corners]), pageColor);
  }
  // Text-like lines inside the page.
  for (var i = 0; i < 14; i++) {
    final y = -ph / 2 + ph * 0.15 + i * ph * 0.05;
    final p1 = rot(-pw * 0.35, y);
    final p2 = rot(pw * 0.35, y);
    cv.line(img, p1, p2, cv.Scalar(30, 30, 30), thickness: 4);
  }
  var out = img;
  if (shadow) {
    // Multiply by a horizontal gradient 0.55..1.0 to fake a soft shadow.
    final grad = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
    for (var x = 0; x < w; x++) {
      final v = (255 * (0.55 + 0.45 * x / w)).round();
      final col = grad.region(cv.Rect(x, 0, 1, h));
      col.setTo(cv.Scalar(v.toDouble(), v.toDouble(), v.toDouble()));
      col.dispose();
    }
    final shaded = cv.multiply(img, grad, scale: 1 / 255);
    grad.dispose();
    img.dispose();
    out = shaded;
  }
  if (lowLight) {
    final dark = cv.convertScaleAbs(out, alpha: 0.35);
    out.dispose();
    out = dark;
  }
  if (noise > 0) {
    final n = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
    cv.randn(n, cv.Scalar.all(0), cv.Scalar.all(noise));
    final noisy = cv.add(out, n);
    n.dispose();
    out.dispose();
    out = noisy;
  }
  final path = p.join(dir.path, '$name.jpg');
  pipe.writeJpeg(out, path, quality: 90);
  out.dispose();
  final quad = Quad.fromUnordered([for (final c in corners) Pt(c.x / w, c.y / h)]);
  return (path, quad);
}

void expectQuadClose(Quad got, Quad exp, {double tol = 0.03, String? reason}) {
  final g = got.points;
  final e = exp.points;
  for (var i = 0; i < 4; i++) {
    expect(g[i].x, closeTo(e[i].x, tol), reason: '${reason ?? ''} corner $i x');
    expect(g[i].y, closeTo(e[i].y, tol), reason: '${reason ?? ''} corner $i y');
  }
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('flashdox_pipe');
  });

  tearDownAll(() async {
    await tmp.delete(recursive: true);
  });

  group('edge detection (synthetic)', () {
    final cases = <String, (String, Quad) Function()>{
      'page on dark table, tilted 4°': () => makeSample(tmp, name: 'a'),
      'pale card on dark, tilted 12°, rounded': () => makeSample(
            tmp,
            name: 'b',
            tiltDeg: 12,
            scale: 0.5,
            rounded: true,
            page: cv.Scalar(225, 230, 220),
          ),
      'dark page on light desk': () => makeSample(
            tmp,
            name: 'c',
            bg: cv.Scalar(225, 225, 225),
            page: cv.Scalar(90, 80, 70),
            tiltDeg: -8,
          ),
      'green card on white': () => makeSample(
            tmp,
            name: 'd',
            bg: cv.Scalar(245, 245, 245),
            page: cv.Scalar(120, 200, 120),
            tiltDeg: 20,
            scale: 0.55,
            rounded: true,
          ),
      'tilted 30°, low light': () => makeSample(
            tmp,
            name: 'e',
            tiltDeg: 30,
            scale: 0.45,
            lowLight: true,
            noise: 10,
          ),
      'large page touching the shadow edge': () => makeSample(
            tmp,
            name: 'f',
            scale: 0.72,
            tiltDeg: 2,
          ),
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final (path, expected) = entry.value();
        final img = pipe.readUpright(path);
        final report = pipe.detectDocument(img);
        img.dispose();
        expect(report.found, isTrue, reason: '$report');
        expectQuadClose(report.quad!, expected, reason: entry.key);
        expect(report.elapsed.inMilliseconds, lessThan(1500));
      });
    }

    test('ID mode finds the card; warp forces the ID-1 shape', () {
      final (path, expected) = makeSample(tmp, name: 'id', scale: 0.5, rounded: true, page: cv.Scalar(200, 220, 200));
      final img = pipe.readUpright(path);
      final r = pipe.detectDocument(img, aspectHint: CardMm.id1Aspect);
      expect(r.found, isTrue, reason: '$r');
      expectQuadClose(r.quad!, expected, tol: 0.04, reason: 'id');
      final warped = pipe.warpToQuad(img, r.quad!, aspect: CardMm.id1Aspect);
      final ratio = warped.cols > warped.rows ? warped.cols / warped.rows : warped.rows / warped.cols;
      expect(ratio, closeTo(CardMm.id1Aspect, 0.01));
      warped.dispose();
      img.dispose();
    });

    test('ID mode searches the guide area first', () {
      final (path, expected) = makeSample(tmp, name: 'guide', scale: 0.45, page: cv.Scalar(210, 215, 220));
      final img = pipe.readUpright(path);
      final cx = expected.points.map((p) => p.x).reduce((a, b) => a + b) / 4;
      final cy = expected.points.map((p) => p.y).reduce((a, b) => a + b) / 4;
      final r = pipe.detectDocument(
        img,
        aspectHint: CardMm.id1Aspect,
        searchArea: (left: cx - 0.3, top: cy - 0.25, right: cx + 0.3, bottom: cy + 0.25),
      );
      img.dispose();
      expect(r.found, isTrue);
      expect(r.strategy, contains('guide area'));
      expectQuadClose(r.quad!, expected, tol: 0.04, reason: 'guide');
    });

    test('returns none on a flat image and on the bare frame', () {
      final flat = cv.Mat.fromScalar(800, 600, cv.MatType.CV_8UC3, cv.Scalar(200, 200, 200));
      expect(pipe.detectDocument(flat).found, isFalse);
      flat.dispose();
    });
  });

  group('render', () {
    test('warps, rotates, filters and caps the long edge', () {
      final (path, quad) = makeSample(tmp, name: 'r');
      for (final filter in FilterType.values) {
        final out = pipe.renderEdits(
          path,
          PageEdits(crop: quad, quarterTurns: 1, filter: filter),
          maxLongEdge: RenderPx.previewLongEdge,
        );
        expect(out.isEmpty, isFalse, reason: '$filter');
        expect(out.cols, greaterThan(out.rows), reason: '$filter');
        expect(math.max(out.cols, out.rows), lessThanOrEqualTo(RenderPx.previewLongEdge));
        expect(out.channels, 3);
        out.dispose();
      }
    });

    test('never enlarges', () {
      final (path, quad) = makeSample(tmp, name: 'small', w: 600, h: 800, scale: 0.5);
      final out = pipe.renderEdits(path, PageEdits(crop: quad), maxLongEdge: 2480);
      expect(math.max(out.cols, out.rows), lessThan(600));
      out.dispose();
    });

    test('Auto whitens a coloured page; ID colour keeps the card colour', () {
      // Reference behaviour: Auto normalises each channel's background to
      // paper white ("a clean, bright page"); ID colour does no whitening.
      final (path, quad) = makeSample(tmp, name: 'green', page: cv.Scalar(120, 200, 120), shadow: false);
      final auto = pipe.renderEdits(path, PageEdits(crop: quad), maxLongEdge: 800);
      final id = pipe.renderEdits(path, PageEdits(crop: quad, filter: FilterType.idColor), maxLongEdge: 800);
      final ma = cv.mean(auto);
      final mi = cv.mean(id);
      expect([ma.val1, ma.val2, ma.val3].every((v) => v > 200), isTrue, reason: 'auto $ma');
      expect(mi.val2, greaterThan(mi.val1 + 30), reason: 'id $mi');
      expect(mi.val2, greaterThan(mi.val3 + 30), reason: 'id $mi');
      auto.dispose();
      id.dispose();
    });

    test('Auto removes a shadow without speckle', () {
      final (path, quad) = makeSample(tmp, name: 'shadow', shadow: true);
      final out = pipe.renderEdits(path, PageEdits(crop: quad), maxLongEdge: 800);
      final gray = cv.cvtColor(out, cv.COLOR_BGR2GRAY);
      final (_, bright) = cv.threshold(gray, 215, 255, cv.THRESH_BINARY);
      expect(cv.countNonZero(bright) / (gray.rows * gray.cols), greaterThan(0.6));
      final (_, dark) = cv.threshold(gray, 60, 255, cv.THRESH_BINARY_INV);
      expect(cv.countNonZero(dark) / (gray.rows * gray.cols), lessThan(0.12));
      for (final x in [out, gray, bright, dark]) {
        x.dispose();
      }
    });

    test('B&W print is pure black or white', () {
      final (path, quad) = makeSample(tmp, name: 'bw');
      final out = pipe.renderEdits(path, PageEdits(crop: quad, filter: FilterType.bwPrint), maxLongEdge: 600);
      final gray = cv.cvtColor(out, cv.COLOR_BGR2GRAY);
      final (_, white) = cv.threshold(gray, 200, 255, cv.THRESH_BINARY);
      final (_, black) = cv.threshold(gray, 55, 255, cv.THRESH_BINARY_INV);
      final total = gray.rows * gray.cols;
      expect((cv.countNonZero(white) + cv.countNonZero(black)) / total, greaterThan(0.95));
      for (final m in [out, gray, white, black]) {
        m.dispose();
      }
    });

    test('OCR render is single-channel at full resolution', () {
      final (path, quad) = makeSample(tmp, name: 'ocr');
      final out = pipe.renderForOcr(path, PageEdits(crop: quad, filter: FilterType.bwPrint));
      expect(out.channels, 1);
      expect(math.max(out.cols, out.rows), greaterThan(900));
      out.dispose();
    });
  });

  group('ownership', () {
    test('fitLongEdge returns the same Mat when small enough and never disposes', () {
      final m = cv.Mat.fromScalar(100, 200, cv.MatType.CV_8UC3, cv.Scalar.all(1));
      expect(identical(pipe.fitLongEdge(m, 500), m), isTrue);
      final small = pipe.fitLongEdge(m, 50);
      expect(identical(small, m), isFalse);
      expect(small.cols, 50);
      expect(m.cols, 200); // untouched
      small.dispose();
      m.dispose();
    });

    test('X-1 / A2: ingest never touches the original, even at 48 MP', () {
      for (final (w, h) in [(4032, 3024), (8064, 6048)]) {
        final big = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar(10, 20, 30));
        final src = p.join(tmp.path, 'big_$w.jpg');
        pipe.writeJpeg(big, src, quality: 80);
        big.dispose();
        final before = File(src).readAsBytesSync();
        final prev = p.join(tmp.path, 'prev_$w.jpg');
        // Twice: a double free would crash on the first or second call.
        for (var i = 0; i < 2; i++) {
          final r = ingestInIsolate(IngestMsg(src, prev, null, null));
          expect((r.width, r.height), (w, h));
        }
        expect(File(src).readAsBytesSync(), before, reason: 'original must be byte-identical');
        final v = pipe.jpegSize(prev)!;
        expect(math.max(v.width, v.height), RenderPx.previewLongEdge);
      }
    });
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
