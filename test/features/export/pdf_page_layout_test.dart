import 'dart:io';

import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/export/data/pdf_builder_impl.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Round 8, P0-8: the image fills the PDF page, like CamScanner.
void main() {
  const a4 = PdfPageFormat.a4;

  test('Auto: an A4-shaped page fills A4 exactly, no margins', () {
    // 2000 × 2900 is 2.6 % taller than A4's 1 : 1.414.
    final (f, fit) = pdfPageLayout(2000, 2900, PdfPageSize.auto);
    expect((f.width, f.height), (a4.width, a4.height));
    expect(fit, pw.BoxFit.fill);
    expect(f.marginLeft + f.marginTop + f.marginRight + f.marginBottom, 0);
  });

  test('Auto: a landscape receipt gets a landscape page of its own shape', () {
    final (f, fit) = pdfPageLayout(3000, 1200, PdfPageSize.auto);
    expect(f.width, closeTo(a4.height, 1e-6), reason: '297 mm wide');
    expect(f.height / f.width, closeTo(1200 / 3000, 1e-9));
    expect(fit, pw.BoxFit.fill);
  });

  test('Auto: a long receipt or an ID card takes its own shape at A4 width', () {
    final (tall, _) = pdfPageLayout(800, 3000, PdfPageSize.auto);
    expect(tall.width, closeTo(a4.width, 1e-6));
    expect(tall.height / tall.width, closeTo(3000 / 800, 1e-9));
    final (card, _) = pdfPageLayout(1011, 638, PdfPageSize.auto);
    expect(card.width, closeTo(a4.height, 1e-6), reason: 'landscape: 297 mm');
    expect(card.height / card.width, closeTo(638 / 1011, 1e-9));
  });

  test('just over 6 % off is no longer stretched', () {
    // A4 ratio 1.4142; 7 % taller.
    final h = (2000 * 1.4142 * 1.07).round();
    final (f, _) = pdfPageLayout(2000, h, PdfPageSize.auto);
    expect(f.height, isNot(closeTo(a4.height, 1)));
  });

  test('A4 / Letter: fitted inside when the shape differs, turned with the image', () {
    final (f, fit) = pdfPageLayout(3000, 1200, PdfPageSize.a4);
    expect((f.width, f.height), (a4.height, a4.width));
    expect(fit, pw.BoxFit.contain);
    final (l, lfit) = pdfPageLayout(2000, 2588, PdfPageSize.letter);
    expect((l.width, l.height), (PdfPageFormat.letter.width, PdfPageFormat.letter.height));
    expect(lfit, pw.BoxFit.fill, reason: 'within 6 % of Letter');
  });

  test('Fit to image: always the image shape', () {
    final (f, fit) = pdfPageLayout(2000, 2900, PdfPageSize.fit);
    expect(f.height / f.width, closeTo(2900 / 2000, 1e-9));
    expect(fit, pw.BoxFit.fill);
  });

  test('a built PDF has the page sizes the layout gives', () async {
    final tmp = await Directory.systemTemp.createTemp('pdf_layout');
    addTearDown(() => tmp.delete(recursive: true));
    String jpg(String name, int w, int h) {
      final m = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar.all(255));
      final path = p.join(tmp.path, '$name.jpg');
      pipe.writeJpeg(m, path, quality: 80);
      m.dispose();
      return path;
    }

    final runner = IsolateRunner();
    final out = await PdfBuilderImpl(runner).fromPages(
      [jpg('page', 1000, 1420), jpg('receipt', 1500, 600)],
      const PdfOptions(),
      outputPath: p.join(tmp.path, 'out.pdf'),
    );
    final text = String.fromCharCodes(out.readAsBytesSync());
    final boxes = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').allMatches(text).map((m) => (double.parse(m[1]!), double.parse(m[2]!))).toList();
    expect(boxes, hasLength(2));
    expect(boxes[0].$1, closeTo(a4.width, 0.5));
    expect(boxes[0].$2, closeTo(a4.height, 0.5));
    expect(boxes[1].$1, closeTo(a4.height, 0.5), reason: 'the receipt page is landscape');
    expect(boxes[1].$2, closeTo(a4.height * 600 / 1500, 0.5));
  });
}
