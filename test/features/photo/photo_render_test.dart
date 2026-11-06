import 'dart:io';

import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/export/data/pdf_builder_impl.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String photo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('photo');
    final img = cv.Mat.fromScalar(4000, 3000, cv.MatType.CV_8UC3, cv.Scalar(200, 180, 160));
    photo = p.join(tmp.path, 'face.jpg');
    cv.imwrite(photo, img);
    img.dispose();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  const edits = PageEdits(
    crop: Quad(tl: Pt(0.2, 0.1), tr: Pt(0.8, 0.1), br: Pt(0.8, 0.6), bl: Pt(0.2, 0.6)),
    filter: FilterType.original,
    outputAspect: 35 / 45,
  );

  test('35 × 45 mm at 300 DPI is 413 × 531 px, portrait, never turned', () {
    final out = pipe.renderSized(photo, edits, widthMm: 35, heightMm: 45, dpi: 300);
    expect((out.cols, out.rows), (413, 531));
    out.dispose();
  });

  test('a small crop is never enlarged', () {
    final small = edits.copyWith(crop: const Quad(tl: Pt(0.45, 0.45), tr: Pt(0.5, 0.45), br: Pt(0.5, 0.5), bl: Pt(0.45, 0.5)));
    final out = pipe.renderSized(photo, small, widthMm: 35, heightMm: 45, dpi: 300);
    expect(out.cols, lessThan(413));
    out.dispose();
  });

  test('photo sheet PDF: one page with the photo', () async {
    final rendered = p.join(tmp.path, 'p.jpg');
    final img = pipe.renderSized(photo, edits, widthMm: 35, heightMm: 45, dpi: 300);
    pipe.writeJpeg(img, rendered, quality: 95);
    img.dispose();
    final runner = IsolateRunner();
    final pdf = await PdfBuilderImpl(runner).photoSheet(
      photoPath: rendered,
      items: PhotoSheetCalculator.layout(const PrintItemSpec(widthMm: 35, heightMm: 45, count: 12)),
      paper: PhotoPaper.a4,
      cutLines: true,
      title: 'Passport photo',
      outputPath: p.join(tmp.path, 'sheet.pdf'),
    );
    final bytes = pdf.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(File(rendered).lengthSync()), reason: 'the photo is embedded once');
    expect(bytes.length, lessThan(File(rendered).lengthSync() * 2), reason: '…not 12 times');
  });
}
