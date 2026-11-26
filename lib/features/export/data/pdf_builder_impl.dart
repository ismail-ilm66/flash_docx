import 'dart:io';
import 'dart:typed_data';

import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/utils/step_timer.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/entities/page_footer.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    final t = StepTimer('PDF ${imagePaths.length} pages');
    final art = options.footer ? await footerArt() : null;
    final bytes = await _runner.run(
      _buildPages,
      _PagesMsg(imagePaths, options.pageSize, options.title, art),
      debugLabel: 'pdfPages',
      priority: JobPriority.interactive,
    );
    t.lap('build (queue + worker) ${bytes.length ~/ 1024} KB');
    return _write(bytes, outputPath, t);
  }

  @override
  Future<File> photoSheet({
    required List<String> photoPaths,
    required List<int> photoOf,
    required List<PlacedItem> items,
    required PhotoPaper paper,
    required bool cutLines,
    required String title,
    required String outputPath,
  }) async {
    final bytes = await _runner.run(
      _buildPhotoSheet,
      _PhotoSheetMsg(photoPaths, photoOf, items, paper, cutLines, title),
      debugLabel: 'pdfPhotos',
      priority: JobPriority.interactive,
    );
    final f = File(outputPath);
    await f.parent.create(recursive: true);
    return f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<File> printSheet(
    PrintLayoutSpec spec, {
    required String outputPath,
  }) async {
    final t = StepTimer('PDF card sheet');
    final bytes = await _runner.run(_buildSheet, spec, debugLabel: 'pdfSheet', priority: JobPriority.interactive);
    t.lap('build (queue + worker) ${bytes.length ~/ 1024} KB');
    return _write(bytes, outputPath, t);
  }

  /// The footer's fonts (Manrope ExtraBold and SemiBold) and the white
  /// mark, read once from the app bundle here: the worker isolate can't.
  static Future<FooterArt>? _art;
  static Future<FooterArt> footerArt() => _art ??= () async {
    Uint8List bytes(ByteData d) => d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    final bold = await rootBundle.load('assets/fonts/Manrope-800.ttf');
    final semi = await rootBundle.load('assets/fonts/Manrope-600.ttf');
    final svg = await rootBundle.loadString('assets/images/flashdox_mark_white.svg');
    return (bold: bytes(bold), semi: bytes(semi), svg: svg);
  }();

  static Future<File> _write(Uint8List bytes, String outputPath, StepTimer t) async {
    final f = File(outputPath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    t
      ..lap('write file')
      ..report();
    return f;
  }
}

/// What the footer is drawn with.
typedef FooterArt = ({Uint8List bold, Uint8List semi, String svg});

class _PagesMsg {
  const _PagesMsg(this.paths, this.size, this.title, this.footer);
  final List<String> paths;
  final PdfPageSize size;
  final String? title;
  final FooterArt? footer;
}

/// The footer badge (round 11, artboard *FooterBadge*): a 6 mm black
/// rounded square with the white mark (4.4 mm) in it, then "Flash Dox:
/// Document Scanner" in 9 pt #111111 (ExtraBold, then SemiBold). Vector;
/// the whole of it links to the store page.
pw.Widget pdfFooter(FooterFonts fonts, String markSvg) => pw.UrlLink(
  destination: PageFooter.url,
  child: pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(
        width: PageFooter.squareMm * _mm,
        height: PageFooter.squareMm * _mm,
        alignment: pw.Alignment.center,
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(PageFooter.squareColor),
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(PageFooter.squareRadiusMm * _mm)),
        ),
        child: pw.SvgImage(svg: markSvg, width: PageFooter.markMm * _mm),
      ),
      pw.SizedBox(width: PageFooter.gapMm * _mm),
      pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: PageFooter.textPt, color: PdfColor.fromInt(PageFooter.textColor)),
          children: [
            pw.TextSpan(text: PageFooter.brand, style: pw.TextStyle(font: fonts.bold)),
            pw.TextSpan(text: PageFooter.tagline, style: pw.TextStyle(font: fonts.semi)),
          ],
        ),
      ),
    ],
  ),
);

typedef FooterFonts = ({pw.Font bold, pw.Font semi});

const double _mm = PdfPageFormat.mm;

/// Round 8, P0-8: the page and how the image sits on it, like CamScanner,
/// where you can't see where the image ends. No margins, ever.
///
/// * The page turns with the image: a landscape image gets a landscape page.
/// * Auto: within 6 % of A4's shape, the image fills A4 (a stretch that
///   small is invisible); otherwise the page takes the image's shape at A4
///   width (receipts, ID cards, book pages).
/// * A4 / Letter: as Auto when close, else the image fits inside, centred.
/// * Fit to image: always the image's shape, at A4 width.
///
/// Round 11 (footer in its own [band] under the page, points): a full A4 /
/// Letter page keeps its size and the image gets the space above the band
/// (210 × 287 mm on A4), filling it when within 3.5 % of its shape, else
/// fitted inside; an image-shaped page grows by the band. Returns the
/// page, how the image sits, and the image area's height.
(PdfPageFormat, pw.BoxFit, double) pdfPageLayout(int imgW, int imgH, PdfPageSize size, {double band = 0}) {
  final landscape = imgW > imgH;
  var base = size == PdfPageSize.letter ? PdfPageFormat.letter : PdfPageFormat.a4;
  if (landscape) base = base.landscape;
  final imgRatio = imgH / imgW;
  final pageRatio = base.height / base.width;
  final close = (imgRatio - pageRatio).abs() / pageRatio <= 0.06;
  final full = PdfPageFormat(base.width, base.height);
  final shapedH = base.width * imgRatio;
  final imageShaped = PdfPageFormat(base.width, shapedH + band);
  // On a full page with a band, the image area is a little shorter.
  final areaRatio = (base.height - band) / base.width;
  final fillsArea = band == 0 ? close : (imgRatio - areaRatio).abs() / areaRatio <= 0.035;
  final fullFit = fillsArea ? pw.BoxFit.fill : pw.BoxFit.contain;
  return switch (size) {
    PdfPageSize.auto => close ? (full, band == 0 ? pw.BoxFit.fill : fullFit, base.height - band) : (imageShaped, pw.BoxFit.fill, shapedH),
    PdfPageSize.fit => (imageShaped, pw.BoxFit.fill, shapedH),
    PdfPageSize.a4 || PdfPageSize.letter => (full, band == 0 ? (close ? pw.BoxFit.fill : pw.BoxFit.contain) : fullFit, base.height - band),
  };
}

Future<Uint8List> _buildPages(_PagesMsg m) async {
  final t = StepTimer('PDF build on worker');
  var reading = 0;
  final doc = pw.Document(title: m.title, creator: 'Flash Dox', compress: true);
  final art = m.footer;
  final fonts = art == null
      ? null
      : (bold: pw.Font.ttf(ByteData.sublistView(art.bold)), semi: pw.Font.ttf(ByteData.sublistView(art.semi)));
  const band = PageFooter.bandMm * _mm;
  for (final path in m.paths) {
    final read = Stopwatch()..start();
    final bytes = File(path).readAsBytesSync();
    final image = pw.MemoryImage(bytes);
    reading += read.elapsedMilliseconds;
    final (format, fit, areaH) = pdfPageLayout(image.width ?? 1000, image.height ?? 1414, m.size, band: fonts == null ? 0 : band);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) {
          final page = pw.SizedBox(
            width: format.width,
            height: areaH,
            child: pw.Center(child: pw.Image(image, fit: fit, width: format.width, height: areaH)),
          );
          if (fonts == null) return page;
          // Round 11: the footer in its own white band, never over the scan.
          return pw.Column(
            children: [
              page,
              pw.Container(
                width: format.width,
                height: format.height - areaH,
                color: PdfColors.white,
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(right: PageFooter.rightMm * _mm),
                child: pdfFooter(fonts, art!.svg),
              ),
            ],
          );
        },
      ),
    );
  }
  t.lap('add ${m.paths.length} pages (reading JPEGs $reading)');
  final out = await doc.save();
  t
    ..lap('save')
    ..report();
  return out;
}

Future<Uint8List> _buildSheet(PrintLayoutSpec spec) async {
  final layout = PrintLayoutCalculator.layout(spec);
  final front = pw.MemoryImage(File(spec.frontPath).readAsBytesSync());
  final back = spec.backPath == null
      ? null
      : pw.MemoryImage(File(spec.backPath!).readAsBytesSync());
  final doc = pw.Document(
    title: spec.title,
    creator: 'Flash Dox',
    compress: true,
  );
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
                    for (final ((x1, y1), (x2, y2))
                        in PrintLayoutCalculator.cropMarks(items)) {
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

class _PhotoSheetMsg {
  const _PhotoSheetMsg(
    this.photos,
    this.photoOf,
    this.items,
    this.paper,
    this.cutLines,
    this.title,
  );
  final List<String> photos;
  final List<int> photoOf;
  final List<PlacedItem> items;
  final PhotoPaper paper;
  final bool cutLines;
  final String title;
}

/// Passport photos at real size; dashed cut lines along every photo edge,
/// run across the gaps so one straight cut serves a whole row or column.
Future<Uint8List> _buildPhotoSheet(_PhotoSheetMsg m) async {
  final photos = [for (final path in m.photos) pw.MemoryImage(File(path).readAsBytesSync())];
  final w = m.paper.widthMm * _mm;
  final h = m.paper.heightMm * _mm;
  final doc = pw.Document(title: m.title, creator: 'Flash Dox', compress: true);
  final xs = {
    for (final it in m.items) ...[it.x, it.x + it.w],
  }.toList()..sort();
  final ys = {
    for (final it in m.items) ...[it.y, it.y + it.h],
  }.toList()..sort();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(w, h),
      build: (_) => pw.Stack(
        children: [
          for (final (i, it) in m.items.indexed)
            pw.Positioned(
              left: it.x * _mm,
              top: it.y * _mm,
              child: pw.Image(
                photos[i < m.photoOf.length ? m.photoOf[i].clamp(0, photos.length - 1) : 0],
                fit: pw.BoxFit.fill,
                width: it.w * _mm,
                height: it.h * _mm,
              ),
            ),
          if (m.cutLines && m.items.isNotEmpty)
            pw.Positioned.fill(
              child: pw.CustomPaint(
                size: PdfPoint(w, h),
                painter: (canvas, size) {
                  canvas
                    ..setStrokeColor(PdfColors.grey500)
                    ..setLineWidth(0.4)
                    ..setLineDashPattern([3, 2]);
                  // pdf's canvas origin is bottom-left; flip y.
                  for (final x in xs) {
                    canvas
                      ..moveTo(x * _mm, size.y - ys.first * _mm + 8)
                      ..lineTo(x * _mm, size.y - ys.last * _mm - 8);
                  }
                  for (final y in ys) {
                    canvas
                      ..moveTo(xs.first * _mm - 8, size.y - y * _mm)
                      ..lineTo(xs.last * _mm + 8, size.y - y * _mm);
                  }
                  canvas.strokePath();
                },
              ),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}
