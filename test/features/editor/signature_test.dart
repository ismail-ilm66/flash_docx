import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// A pen scribble on white paper under uneven light, with sensor noise.
String _scribblePhoto(Directory dir) {
  const w = 1600;
  const h = 1200;
  final grad = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
  for (var x = 0; x < w; x += 40) {
    // Light falls off to the right: 235 → 165.
    final v = 235 - (70 * x / w).round();
    cv.rectangle(grad, cv.Rect(x, 0, 40, h), cv.Scalar(v.toDouble(), v.toDouble(), v + 3.0), thickness: -1);
  }
  final pts = <cv.Point>[for (var i = 0; i <= 60; i++) cv.Point(500 + i * 10, 600 + (60 * math.sin(i / 4)).round())];
  cv.polylines(grad, cv.VecVecPoint.fromList([pts]), false, cv.Scalar(90, 40, 20), thickness: 7);
  cv.line(grad, cv.Point(520, 690), cv.Point(1080, 670), cv.Scalar(90, 40, 20), thickness: 5);
  final noise = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
  cv.randn(noise, cv.Scalar.all(0), cv.Scalar.all(6));
  final photo = cv.add(grad, noise);
  final path = p.join(dir.path, 'scribble.jpg');
  cv.imwrite(path, photo);
  for (final m in [grad, noise, photo]) {
    m.dispose();
  }
  return path;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sig'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('scan from paper: transparent PNG trimmed to the ink, paper removed', () {
    final out = p.join(tmp.path, 'sig.png');
    pipe.signatureFromPhoto(_scribblePhoto(tmp), out);
    final png = cv.imread(out, flags: cv.IMREAD_UNCHANGED);
    expect(png.channels, 4);
    // Trimmed: the scribble spans ~600 × 190 px of a 1600 × 1200 photo.
    expect(png.cols, inInclusiveRange(560, 700));
    expect(png.rows, inInclusiveRange(150, 260));
    final alpha = cv.split(png)[3];
    final inked = alpha.data.where((v) => v > 128).length / (png.cols * png.rows);
    expect(inked, inInclusiveRange(0.03, 0.4), reason: 'strokes opaque, paper transparent');
    // Corners are paper, including the dark right-hand side.
    expect(alpha.at<int>(2, 2), lessThan(20));
    expect(alpha.at<int>(png.rows - 3, png.cols - 3), lessThan(20));
    png.dispose();
  });

  test('a blank page is not a signature', () {
    final blank = cv.Mat.fromScalar(900, 1200, cv.MatType.CV_8UC3, cv.Scalar.all(230));
    final path = p.join(tmp.path, 'blank.jpg');
    cv.imwrite(path, blank);
    expect(() => pipe.signatureFromPhoto(path, p.join(tmp.path, 'x.png')), throwsStateError);
  });

  test('overlays: fitted into their rect, inked, alpha blended; nothing outside', () {
    // A 200 × 100 opaque bar on a transparent PNG.
    final sig = cv.Mat.zeros(100, 200, cv.MatType.CV_8UC4);
    cv.rectangle(sig, cv.Rect(0, 40, 200, 20), cv.Scalar(0, 0, 0, 255), thickness: -1);
    final sigPath = p.join(tmp.path, 'bar.png');
    cv.imwrite(sigPath, sig);
    final page = cv.Mat.fromScalar(1000, 800, cv.MatType.CV_8UC1, cv.Scalar.all(250)); // grayscale page
    final out = pipe.withOverlays(page, [
      PageOverlay(id: 'a', kind: OverlayKind.signature, imagePath: sigPath, left: 0.1, top: 0.5, width: 0.5, height: 0.25),
    ]);
    expect(out.channels, 3, reason: 'blue ink needs colour');
    // Rect = x 80..480, y 500..750; the 2:1 PNG fits as 400 × 200, centred
    // at y 525..725 → the bar (rows 40..60 of 100) is y 605..645.
    final bar = out.at<cv.Vec3b>(625, 280);
    expect([bar.val1, bar.val2, bar.val3], [174, 63, 31], reason: 'blue ink (BGR)');
    final paper = out.at<cv.Vec3b>(560, 280);
    expect([paper.val1, paper.val2, paper.val3], [250, 250, 250], reason: 'transparent part untouched');
    final outside = out.at<cv.Vec3b>(625, 600);
    expect(outside.val1, 250);

    final black = pipe.withOverlays(page, [
      PageOverlay(id: 'a', kind: OverlayKind.signature, imagePath: sigPath, left: 0.1, top: 0.5, width: 0.5, height: 0.25, ink: InkColor.black),
    ]);
    expect(black.at<cv.Vec3b>(625, 280).val1, 26);
    expect(identical(pipe.withOverlays(page, const []), page), isTrue);
    for (final m in [sig, page, out, black]) {
      m.dispose();
    }
  });

  test('renderEdits composites overlays last, in page space', () {
    final photo = cv.Mat.fromScalar(1200, 900, cv.MatType.CV_8UC3, cv.Scalar.all(240));
    final photoPath = p.join(tmp.path, 'page.jpg');
    cv.imwrite(photoPath, photo);
    final sig = cv.Mat.fromScalar(50, 50, cv.MatType.CV_8UC4, cv.Scalar(0, 0, 0, 255));
    final sigPath = p.join(tmp.path, 'sq.png');
    cv.imwrite(sigPath, sig);
    final edits = PageEdits(
      filter: FilterType.original,
      overlays: [PageOverlay(id: 'a', kind: OverlayKind.date, imagePath: sigPath, left: 0.5, top: 0.5, width: 0.1, height: 0.1, ink: InkColor.black)],
    );
    final out = pipe.renderEdits(photoPath, edits);
    expect(out.at<cv.Vec3b>(660, 495).val1, closeTo(26, 3));
    expect(out.at<cv.Vec3b>(100, 100).val1, closeTo(240, 3));
    final ocr = pipe.renderForOcr(photoPath, edits);
    expect(ocr.at<int>(660, 495), greaterThan(200), reason: 'OCR never sees the signature');
    for (final m in [photo, sig, out, ocr]) {
      m.dispose();
    }
  });
}
