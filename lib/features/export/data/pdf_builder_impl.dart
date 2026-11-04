import 'dart:io';
import 'dart:typed_data';

import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:injectable/injectable.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

@LazySingleton(as: PdfBuilder)
class PdfBuilderImpl implements PdfBuilder {
  PdfBuilderImpl(this._runner);

  final IsolateRunner _runner;

  @override
  Future<File> fromPages(
    List<String> imagePaths,
    PdfOptions options, {
    required String outputPath,
  }) async {
    final bytes = await _runner.run(
      _buildPages,
      _PagesMsg(imagePaths, options.pageSize, options.title),
      debugLabel: 'pdfPages',
    );
    final f = File(outputPath);
    await f.parent.create(recursive: true);
    return f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<File> printSheet(PrintLayoutSpec spec, {required String outputPath}) async {
    final bytes = await _runner.run(_buildSheet, spec, debugLabel: 'pdfSheet');
    final f = File(outputPath);
    await f.parent.create(recursive: true);
    return f.writeAsBytes(bytes, flush: true);
  }
}

class _PagesMsg {
  const _PagesMsg(this.paths, this.size, this.title);
  final List<String> paths;
  final PdfPageSize size;
  final String? title;
}

const double _mm = PdfPageFormat.mm;
const double _fitDpi = 200;

Future<Uint8List> _buildPages(_PagesMsg m) async {
  final doc = pw.Document(title: m.title, creator: 'Flash Dox', compress: true);
  for (final path in m.paths) {
    final bytes = File(path).readAsBytesSync();
    final image = pw.MemoryImage(bytes);
    final PdfPageFormat format;
    if (m.size == PdfPageSize.fit) {
      final w = (image.width ?? 1000) / _fitDpi * PdfPageFormat.inch;
      final h = (image.height ?? 1400) / _fitDpi * PdfPageFormat.inch;
      format = PdfPageFormat(w, h);
    } else {
      format = PdfPageFormat(
        m.size.widthMm! * _mm,
        m.size.heightMm! * _mm,
        marginAll: 8 * _mm,
      );
    }
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
  }
  return doc.save();
}

Future<Uint8List> _buildSheet(PrintLayoutSpec spec) async {
  final layout = PrintLayoutCalculator.layout(spec);
  final front = pw.MemoryImage(File(spec.frontPath).readAsBytesSync());
  final back = spec.backPath == null
      ? null
      : pw.MemoryImage(File(spec.backPath!).readAsBytesSync());
  final doc = pw.Document(title: spec.title, creator: 'Flash Dox', compress: true);
  const format = PdfPageFormat(
    PrintLayoutCalculator.sheetW * _mm,
    PrintLayoutCalculator.sheetH * _mm,
  );
  for (final items in layout.pages) {
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Stack(
          children: [
            if (spec.cutGuides && spec.output != PrintOutput.image)
              pw.Positioned.fill(
                child: pw.CustomPaint(
                  size: const PdfPoint(
                    PrintLayoutCalculator.sheetW * _mm,
                    PrintLayoutCalculator.sheetH * _mm,
                  ),
                  painter: (canvas, size) {
                    canvas
                      ..setStrokeColor(PdfColors.grey400)
                      ..setLineWidth(0.3);
                    // pdf's canvas origin is bottom-left; flip y.
                    for (final ((x1, y1), (x2, y2)) in PrintLayoutCalculator.cropMarks(items)) {
                      canvas
                        ..moveTo(x1 * _mm, size.y - y1 * _mm)
                        ..lineTo(x2 * _mm, size.y - y2 * _mm);
                    }
                    canvas.strokePath();
                  },
                ),
              ),
            for (final it in items)
              pw.Positioned(
                left: it.x * _mm,
                top: it.y * _mm,
                child: pw.SizedBox(
                  width: it.w * _mm,
                  height: it.h * _mm,
                  child: pw.Transform.rotateBox(
                    angle: it.rotated ? -1.5707963267948966 : 0,
                    child: pw.Image(
                      it.isBack ? (back ?? front) : front,
                      fit: pw.BoxFit.fill,
                      width: (it.rotated ? it.h : it.w) * _mm,
                      height: (it.rotated ? it.w : it.h) * _mm,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
