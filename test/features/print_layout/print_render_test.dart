import 'dart:io';

import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// P1-9: cards render from the original at real size for the chosen DPI.
void main() {
  late Directory tmp;
  late String bigPhoto;
  late String smallPhoto;
  const crop = Quad(tl: Pt(0.1, 0.2), tr: Pt(0.9, 0.2), br: Pt(0.9, 0.7), bl: Pt(0.1, 0.7));
  const edits = PageEdits(crop: crop, filter: FilterType.original, outputAspect: 85.6 / 54);

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('print');
    for (final (name, w, h) in [('big', 4000, 3000), ('small', 800, 600)]) {
      final m = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar(120, 140, 160));
      pipe.writeJpeg(m, p.join(tmp.path, '$name.jpg'));
      m.dispose();
    }
    bigPhoto = p.join(tmp.path, 'big.jpg');
    smallPhoto = p.join(tmp.path, 'small.jpg');
  });

  tearDownAll(() => tmp.delete(recursive: true));

  test('the ID colour filter at 2x print size looks like the export-size render', () {
    // A busy card: fine lines and noise, where filtering at another scale
    // would show.
    final m = cv.Mat.fromScalar(3000, 4000, cv.MatType.CV_8UC3, cv.Scalar(150, 170, 190));
    for (var y = 700; y < 2000; y += 23) {
      cv.line(m, cv.Point(500, y), cv.Point(3500, y + 40), cv.Scalar(60, 70, 90), thickness: 3);
    }
    final n = cv.Mat.zeros(3000, 4000, cv.MatType.CV_8UC3);
    cv.randn(n, cv.Scalar.all(0), cv.Scalar.all(8));
    final noisy = cv.add(m, n);
    final path = p.join(tmp.path, 'busy.jpg');
    pipe.writeJpeg(noisy, path, quality: 92);
    for (final x in [m, n, noisy]) {
      x.dispose();
    }
    const id = PageEdits(crop: crop, filter: FilterType.idColor, outputAspect: 85.6 / 54);
    final card = pipe.renderCard(path, id, widthMm: 85.6, heightMm: 54, dpi: 300);
    // Filtered at export size (the cleaned base's 2000 px), then shrunk.
    // Not the full camera image: since the round 6 denoise works at full
    // resolution, filtering a 12 MP page leaves more noise in the level
    // statistics and the result is darker; every render now shares the
    // export-size scale instead.
    final full = pipe.renderEdits(path, id, maxLongEdge: 2000);
    final old = cv.resize(full, (card.cols, card.rows), interpolation: cv.INTER_AREA);
    // Same picture: the fine texture differs (the sharpening now works at
    // print scale, a little crisper), so compare at a light blur.
    final a = cv.gaussianBlur(card, (5, 5), 1.5);
    final b = cv.gaussianBlur(old, (5, 5), 1.5);
    final psnr = cv.PSNR(a, b);
    expect(psnr, greaterThan(32), reason: 'PSNR $psnr dB');
    final (mn, mo) = (cv.mean(card), cv.mean(old));
    for (final (x, y) in [(mn.val1, mo.val1), (mn.val2, mo.val2), (mn.val3, mo.val3)]) {
      expect(x, closeTo(y, 4), reason: 'brightness kept');
    }
    for (final x in [card, full, old, a, b]) {
      x.dispose();
    }
  });

  test('ID card at 300 DPI is 1011 × 638 px; at 600 DPI 2022 × 1276 px', () {
    for (final (dpi, w, h) in [(300, 1011, 638), (600, 2022, 1276)]) {
      final card = pipe.renderCard(bigPhoto, edits, widthMm: 85.6, heightMm: 54, dpi: dpi);
      expect((card.cols, card.rows), (w, h), reason: '$dpi DPI');
      card.dispose();
    }
  });

  test('never enlarges a low-resolution photo (High = native when lower)', () {
    final card = pipe.renderCard(smallPhoto, edits, widthMm: 85.6, heightMm: 54, dpi: 600);
    expect(card.cols, lessThan(2022));
    expect(card.cols / card.rows, closeTo(85.6 / 54, 0.01));
    card.dispose();
  });

  test('a portrait render is turned to landscape', () {
    final card = pipe.renderCard(
      bigPhoto,
      edits.copyWith(quarterTurns: 1),
      widthMm: 85.6,
      heightMm: 54,
      dpi: 300,
    );
    expect(card.cols, greaterThan(card.rows));
    card.dispose();
  });

  test('the one-image sheet has the pixel size of its DPI and is encoded once from the originals', () async {
    final renderer = SheetImageRenderer(IsolateRunner());
    const spec = PrintLayoutSpec(kind: PrintKind.idCard, output: PrintOutput.image, copies: 1, frontPath: '', backPath: '');
    final box = PrintLayoutCalculator.pageSize(spec);
    for (final dpi in [300, 600]) {
      final out = await renderer.render(
        spec,
        front: (originalPath: bigPhoto, edits: edits),
        back: (originalPath: bigPhoto, edits: edits),
        dpi: dpi,
        outputPath: p.join(tmp.path, 'sheet_$dpi.jpg'),
      );
      final size = pipe.jpegSize(out)!;
      expect(size.width, (box.w / 25.4 * dpi).round());
      expect(size.height, (box.h / 25.4 * dpi).round());
    }
  });
}
