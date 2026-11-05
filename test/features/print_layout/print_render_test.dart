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
    final box = PrintLayoutCalculator.contentBox(PrintLayoutCalculator.layout(spec).pages.first);
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
