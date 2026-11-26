import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/reduce/domain/reduce_options.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

/// Round 11, section F: Reduce size, for "the portal says under 200 KB".
/// The original file is never changed; results go to the export temp
/// folder (cleared on launch).
@lazySingleton
class ReduceService {
  ReduceService(this._processor, this._pdf, this._files, this._prefs, this._export);

  final ImageProcessor _processor;
  final PdfBuilder _pdf;
  final FileStore _files;
  final PrefsService _prefs;
  final ExportDocument _export;

  /// Pages of other PDFs are rendered at this many dots per inch.
  static const double pdfDpi = 150;

  /// Smallest long edge the search goes down to.
  static const int minEdge = 800;

  Directory _outDir() => Directory(p.join(_files.exportTemp.path, 'reduce_${newId()}'))..createSync(recursive: true);

  static int _size(String path) => File(path).existsSync() ? File(path).lengthSync() : 0;

  /// Each image under [maxBytes] (no footer on reduced images).
  Future<Either<Failure, ReduceResult>> images(
    List<String> paths, {
    required int maxBytes,
    required PixelSize size,
    required ReduceFormat format,
  }) async {
    try {
      final dir = _outDir();
      final outs = <String>[];
      var after = 0;
      var fits = true;
      for (final (i, src) in paths.indexed) {
        final base = p.basenameWithoutExtension(src);
        final out = p.join(dir.path, '${base.isEmpty ? 'image_${i + 1}' : base}_small.${format.extension}');
        final r = await _processor.reduceImage(
          src,
          outputPath: out,
          maxBytes: maxBytes,
          boxW: size.width,
          boxH: size.height,
          exact: size.exact,
          longSide: size.longSide,
        );
        outs.add(out);
        after += r.bytes;
        fits &= r.fits;
      }
      return Right(
        ReduceResult(
          files: outs,
          bytesBefore: paths.fold(0, (s, f) => s + _size(f)),
          bytesAfter: after,
          fits: fits,
          count: paths.length,
        ),
      );
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
  }

  /// Any PDF on the phone: each page rendered to a picture ([pdfDpi]), the
  /// Max file size search, a new PDF (with the footer setting). With
  /// [anyway] the smallest possible is made when [maxBytes] can't be met.
  Future<Either<Failure, ReduceResult>> pdf(String path, {required int maxBytes, bool anyway = false}) async {
    try {
      final dir = _outDir();
      final bytes = await File(path).readAsBytes();
      final pages = <String>[];
      await for (final raster in Printing.raster(bytes, dpi: pdfDpi)) {
        final out = p.join(dir.path, 'page_${pages.length + 1}.png');
        await File(out).writeAsBytes(await raster.toPng(), flush: true);
        pages.add(out);
      }
      if (pages.isEmpty) return const Left(PdfFailure('no pages'));
      final outputs = [for (var i = 0; i < pages.length; i++) p.join(dir.path, 'small_${i + 1}.jpg')];
      final overhead = 3000 + 1200 * pages.length;
      Future<ShrinkOutcome> shrink(int target, {bool gray = false}) => _processor.shrinkPages(
        pages,
        targetBytes: target,
        overheadBytes: overhead,
        grayscale: gray,
        outputs: outputs,
        minEdge: minEdge,
      );
      var outcome = await shrink(maxBytes);
      var fits = outcome is ShrinkFits;
      if (outcome is ShrinkNeedsGrayscale || outcome is ShrinkCantFit) {
        final smallest = switch (outcome) {
          ShrinkNeedsGrayscale(:final smallestBytes) || ShrinkCantFit(:final smallestBytes) => smallestBytes,
          ShrinkFits() => 0,
        };
        if (!anyway) {
          return Right(
            ReduceResult(files: const [], bytesBefore: bytes.length, bytesAfter: smallest + overhead, fits: false, count: pages.length),
          );
        }
        outcome = await shrink(smallest + overhead);
        fits = false;
      }
      final name = '${p.basenameWithoutExtension(path)}_small.pdf';
      final out = await _pdf.fromPages(
        outputs,
        PdfOptions(pageSize: PdfPageSize.fit, title: p.basenameWithoutExtension(path), footer: _prefs.exportFooter),
        outputPath: p.join(dir.path, name),
      );
      return Right(
        ReduceResult(files: [out.path], bytesBefore: bytes.length, bytesAfter: out.lengthSync(), fits: fits && out.lengthSync() <= maxBytes, count: pages.length),
      );
    } catch (e) {
      return Left(PdfFailure(e.toString()));
    }
  }

  /// A Flash Dox document, rebuilt from its full-size pages with the same
  /// search (the Max file size export).
  Future<Either<Failure, ReduceResult>> document(ScanDocument doc, {required int maxBytes, bool anyway = false}) async {
    final before = doc.pages.fold(0, (s, pg) => s + _size(pg.originalPath));
    var options = ExportOptions(format: ExportFormat.pdf, layout: ExportLayout.separate, maxBytes: maxBytes, fileName: doc.title, footer: _prefs.exportFooter);
    var r = await _export.prepare(doc, options);
    // Too big in colour: black and white first, then (when asked) the
    // smallest it can be.
    if (r.getLeft().toNullable() case ShrinkFailure(:final canTryGrayscale) when canTryGrayscale) {
      options = options.copyWith(grayscaleToFit: true);
      r = await _export.prepare(doc, options);
    }
    final failed = r.getLeft().toNullable();
    if (failed is ShrinkFailure) {
      if (!anyway) {
        return Right(ReduceResult(files: const [], bytesBefore: before, bytesAfter: failed.smallestBytes, fits: false, count: doc.pages.length));
      }
      r = await _export.prepare(doc, options.copyWith(maxBytes: failed.smallestBytes + 4000));
    }
    return r.map(
      (prepared) => ReduceResult(
        files: [for (final f in prepared.files) f.path],
        bytesBefore: before,
        bytesAfter: prepared.files.fold(0, (s, f) => s + f.lengthSync()),
        fits: failed == null,
        count: doc.pages.length,
      ),
    );
  }
}
