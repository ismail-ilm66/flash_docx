import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/string_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/core/utils/step_timer.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flash_dox/features/print_layout/domain/usecases/build_print_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Files built by [ExportDocument.prepare].
class PreparedExport {
  const PreparedExport(this.files, {this.shrunk});

  final List<File> files;

  /// The settings Max file size settled on, if it was used.
  final ShrinkStep? shrunk;

  int get bytes => files.fold(0, (sum, f) => sum + f.lengthSync());
}

/// Builds the export in two steps (P0-4 point 6):
///
/// * [prepare] renders pages and builds the PDF / image set into a staging
///   folder. The Share sheet starts it on open, so the file is usually ready
///   by the time the user taps Share. Page JPEGs are cached per look, size
///   and quality, so a page-size or format change reuses them.
/// * [deliver] gives the prepared files their final names and shares or
///   saves them.
@injectable
class ExportDocument {
  ExportDocument(
    this._render,
    this._pdf,
    this._files,
    this._share,
    this._save,
    this._repo,
    this._sheet,
    this._processor,
  );

  final PageRenderService _render;
  final PdfBuilder _pdf;
  final FileStore _files;
  final ShareService _share;
  final SaveService _save;
  final DocumentRepository _repo;
  final SheetImageRenderer _sheet;
  final ImageProcessor _processor;

  /// True when the document is a two-sided card and the user asked for both
  /// sides in one picture / one PDF page.
  static bool usesOneImage(ScanDocument doc, ExportOptions o) =>
      doc.mode.supportsPrintLayout &&
      doc.pages.length >= 2 &&
      o.layout == ExportLayout.oneImage;

  /// True when Max file size applies: a page-per-page PDF with a limit.
  /// Max file size is offered for a page-per-page PDF, and for a passport
  /// photo saved as JPG (forms often cap the photo size).
  /// Round 10, P1-1: a rough size per page for the Quality buttons
  /// ("Standard · ~0.4 MB per page"). An A4-shaped page at the export size;
  /// bytes per pixel from typical scanned pages at that JPEG quality.
  static int estimatePageBytes(ExportOptions o) {
    final long = o.quality == ExportQuality.high ? 3000 : RenderPx.standardExportLongEdge;
    final px = long * long / 1.414;
    final perPixel = switch ((o.format, o.quality)) {
      (ExportFormat.png, _) => 0.9,
      (_, ExportQuality.high) => 0.19,
      (_, ExportQuality.standard) => 0.14,
    };
    return (px * perPixel).round();
  }

  static bool canShrink(ScanDocument doc, ExportOptions o) =>
      !usesOneImage(doc, o) &&
      (o.format == ExportFormat.pdf ||
          (doc.mode == ScanMode.photo && o.format == ExportFormat.jpg));

  /// …and applies when a limit is set.
  static bool shrinks(ScanDocument doc, ExportOptions o) =>
      o.maxBytes != null && canShrink(doc, o);

  /// Number of steps [prepare] reports through `onStep`.
  static int stepsFor(ScanDocument doc, ExportOptions o) =>
      usesOneImage(doc, o) ? 2 : doc.pages.length + (shrinks(doc, o) ? 1 : 0);

  /// Prepare then deliver, in one go.
  Future<Either<Failure, Unit>> call(
    ScanDocument doc,
    ExportOptions options,
    ExportTarget target,
  ) async {
    final r = await prepare(doc, options);
    return r.fold(
      (f) async => Left(f),
      (prepared) => deliver(doc, prepared.files, options, target),
    );
  }

  Future<Either<Failure, PreparedExport>> prepare(
    ScanDocument doc,
    ExportOptions options, {
    void Function(int done, int total)? onStep,
    CancelToken? cancel,
  }) async {
    final pages = doc.sortedPages;
    if (pages.isEmpty) return const Left(NotFoundFailure());
    final size = options.quality == ExportQuality.high
        ? RenderSize.full
        : RenderSize.standard;
    final jpegQ = options.quality == ExportQuality.high
        ? Limits.highJpegQuality
        : Limits.standardJpegQuality;
    final imgExt = options.format == ExportFormat.png ? 'png' : 'jpg';
    // One staging folder per set of options, so an older, superseded job
    // never writes over a newer one.
    final staging = _files.exportPath(
      'ready_${doc.id}_${Object.hash(options.format, options.quality, options.pageSize, options.layout).toUnsigned(32)}',
    );
    final total = stepsFor(doc, options);
    bool cancelled() => cancel?.isCancelled ?? false;

    if (shrinks(doc, options)) {
      return _prepareShrunk(
        doc,
        options,
        staging,
        onStep: onStep,
        cancel: cancel,
      );
    }

    if (usesOneImage(doc, options)) {
      // Front above back at real size (P1-2), straight from the originals at
      // 300 DPI (Standard) or 600 DPI (High), encoded once.
      final kind = doc.mode == ScanMode.passport
          ? PrintKind.passport
          : PrintKind.idCard;
      final card = PrintLayoutCalculator.cardSize(kind);
      final dpi = BuildPrintLayout.dpiFor(options.quality);
      final front = doc.pageOfSide(CardSide.front) ?? pages[0];
      final back = doc.pageOfSide(CardSide.back) ?? pages[1];
      try {
        onStep?.call(0, total);
        if (options.isImage) {
          final spec = PrintLayoutSpec(
            kind: kind,
            output: PrintOutput.image,
            copies: 1,
            frontPath: '',
            backPath: '',
            title: doc.title,
            cutGuides: false,
          );
          final out = await _sheet.render(
            spec,
            front: (originalPath: front.originalPath, edits: front.edits),
            back: (originalPath: back.originalPath, edits: back.edits),
            dpi: dpi,
            jpegQuality: jpegQ,
            outputPath: p.join(staging, 'card.$imgExt'),
          );
          onStep?.call(total, total);
          return Right(PreparedExport([File(out)]));
        }
        Future<String> side(ScanPage pg, String name) => _render.renderCardSide(
          pg,
          widthMm: card.w,
          heightMm: card.h,
          dpi: dpi,
          outputPath: p.join(staging, '$name.jpg'),
        );
        final t = StepTimer('share prepare card PDF ${options.quality.name}');
        final frontPath = await side(front, 'front');
        t.lap('front side (queue + worker)');
        onStep?.call(1, total);
        if (cancelled()) return const Left(CancelledFailure());
        final spec = PrintLayoutSpec(
          kind: kind,
          output: PrintOutput.pdfOnePage,
          copies: 1,
          frontPath: frontPath,
          backPath: await side(back, 'back'),
          title: doc.title,
          cutGuides: false,
        );
        t.lap('back side (queue + worker)');
        final pdf = await _pdf.printSheet(
          spec,
          outputPath: p.join(staging, 'doc.pdf'),
        );
        t
          ..lap('PDF')
          ..report();
        onStep?.call(total, total);
        return Right(PreparedExport([pdf]));
      } catch (e) {
        return Left(
          options.isImage
              ? ImageProcessingFailure(e.toString())
              : PdfFailure(e.toString()),
        );
      }
    }

    // Each page: rendered from the original, encoded once; a PDF embeds
    // those JPEGs as they are, a JPG export shares them as they are.
    final rendered = <String>[];
    final card = PageRenderService.isCard(doc.mode);
    final t = StepTimer('share prepare ${pages.length} pages ${options.format.name} ${options.quality.name}');
    try {
      onStep?.call(0, total);
      for (final (i, page) in pages.indexed) {
        if (cancelled()) return const Left(CancelledFailure());
        if (options.format == ExportFormat.png) {
          rendered.add(
            await _render.renderExportPage(
              page,
              size: size,
              outputPath: p.join(staging, 'page_${i + 1}.png'),
              jpegQuality: jpegQ,
              card: card,
            ),
          );
          t.lap('page ${i + 1} rendered (queue + worker)');
        } else {
          final cached = _files.exportPagePath(
            doc.id,
            page.id,
            page.originalPath,
            page.edits,
            sizeKey: size.name,
            jpegQuality: jpegQ,
          );
          if (File(cached).existsSync()) {
            _touch(cached);
            t.lap('page ${i + 1} from cache');
          } else if (await _render.joinWarm(cached)) {
            t.lap('page ${i + 1} from the warm-up render');
          } else {
            // Written under a temp name and renamed, so a cancelled or failed
            // render never leaves half a JPEG in the cache.
            final tmp = '${p.withoutExtension(cached)}.part.jpg';
            await _render.renderExportPage(
              page,
              size: size,
              outputPath: tmp,
              jpegQuality: jpegQ,
              card: card,
            );
            File(tmp).renameSync(cached);
            await _files.pruneExportPages(doc.id, page.id, size.name, keep: cached);
            t.lap('page ${i + 1} rendered (queue + worker)');
          }
          rendered.add(cached);
        }
        // A passport photo at the exact pixel size a form asks for.
        if (options.isImage &&
            doc.mode == ScanMode.photo &&
            options.hasPixelSize) {
          rendered[i] = await _processor.resizeExact(
            rendered[i],
            options.pixelWidth!,
            options.pixelHeight!,
            outputPath: p.join(
              staging,
              'page_${i + 1}_${options.pixelWidth}x${options.pixelHeight}.${options.extension}',
            ),
            jpegQuality: jpegQ,
          );
        }
        onStep?.call(i + 1, total);
      }
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
    if (options.isImage) {
      t.report();
      return Right(PreparedExport(rendered.map(File.new).toList()));
    }
    if (cancelled()) return const Left(CancelledFailure());
    try {
      final pdf = await _pdf.fromPages(
        rendered,
        PdfOptions(pageSize: options.pageSize, title: doc.title),
        outputPath: p.join(staging, 'doc.pdf'),
      );
      t
        ..lap('PDF')
        ..report();
      return Right(PreparedExport([pdf]));
    } catch (e) {
      return Left(PdfFailure(e.toString()));
    }
  }

  /// Max file size (feature 2): renders each page once at 2000 px, then
  /// lets [ShrinkToFit] pick the best settings that fit. The PDF overhead
  /// is estimated first and corrected once from the real file if needed.
  Future<Either<Failure, PreparedExport>> _prepareShrunk(
    ScanDocument doc,
    ExportOptions options,
    String staging, {
    void Function(int done, int total)? onStep,
    CancelToken? cancel,
  }) async {
    final pages = doc.sortedPages;
    final total = stepsFor(doc, options);
    final target = options.maxBytes!;
    final bases = <String>[];
    try {
      onStep?.call(0, total);
      for (final (i, page) in pages.indexed) {
        if (cancel?.isCancelled ?? false) return const Left(CancelledFailure());
        final base = _files.exportPagePath(
          doc.id,
          page.id,
          page.originalPath,
          page.edits,
          sizeKey: 'shrinkBase',
          jpegQuality: _baseQuality,
        );
        if (File(base).existsSync()) {
          _touch(base);
        } else {
          final tmp = '${p.withoutExtension(base)}.part.jpg';
          await _render.renderExportPage(
            page,
            size: RenderSize.standard,
            outputPath: tmp,
            jpegQuality: _baseQuality,
            card: PageRenderService.isCard(doc.mode),
          );
          File(tmp).renameSync(base);
          await _files.pruneExportPages(doc.id, page.id, 'shrinkBase', keep: base);
        }
        // An exact pixel size is fixed first; the search then only lowers
        // the JPEG quality (its edges never go below that size).
        bases.add(
          options.isImage && options.hasPixelSize
              ? await _processor.resizeExact(
                  base,
                  options.pixelWidth!,
                  options.pixelHeight!,
                  outputPath: p.join(
                    staging,
                    'base_${i + 1}_${options.pixelWidth}x${options.pixelHeight}.jpg',
                  ),
                  jpegQuality: _baseQuality,
                )
              : base,
        );
        onStep?.call(i + 1, total);
      }
      if (cancel?.isCancelled ?? false) return const Left(CancelledFailure());

      // A JPG photo is the file itself: no PDF around it, smaller sizes
      // allowed, and never black and white.
      final image = options.isImage;
      var overhead = image
          ? 0
          : _pdfOverheadBase + _pdfOverheadPerPage * pages.length;
      final outputs = [
        for (var i = 0; i < pages.length; i++)
          p.join(staging, 'page_${i + 1}.jpg'),
      ];
      for (var attempt = 0; attempt < 2; attempt++) {
        final outcome = await _processor.shrinkPages(
          bases,
          targetBytes: target,
          overheadBytes: overhead,
          grayscale: !image && options.grayscaleToFit,
          outputs: outputs,
          minEdge: !image
              ? ShrinkToFit.minEdge
              : options.hasPixelSize
              ? math.max(options.pixelWidth!, options.pixelHeight!)
              : ShrinkToFit.photoMinEdge,
        );
        switch (outcome) {
          case ShrinkNeedsGrayscale(:final smallestBytes):
            return Left(
              ShrinkFailure(
                targetBytes: target,
                smallestBytes: smallestBytes,
                canTryGrayscale: !image,
              ),
            );
          case ShrinkCantFit(:final smallestBytes):
            return Left(
              ShrinkFailure(
                targetBytes: target,
                smallestBytes: smallestBytes,
                canTryGrayscale: false,
              ),
            );
          case ShrinkFits(:final step, :final bytes) when image:
            debugPrint('[shrink] photo $step -> $bytes bytes (target $target)');
            onStep?.call(total, total);
            return Right(
              PreparedExport([for (final o in outputs) File(o)], shrunk: step),
            );
          case ShrinkFits(:final step, :final bytes):
            final pdf = await _pdf.fromPages(
              outputs,
              PdfOptions(pageSize: options.pageSize, title: doc.title),
              outputPath: p.join(staging, 'doc.pdf'),
            );
            final size = pdf.lengthSync();
            debugPrint(
              '[shrink] $step -> $size bytes (target $target, estimate $bytes)',
            );
            if (size <= target) {
              onStep?.call(total, total);
              return Right(PreparedExport([pdf], shrunk: step));
            }
            // The real overhead was bigger than estimated: search again.
            overhead += size - bytes;
        }
      }
      return Left(
        ShrinkFailure(
          targetBytes: target,
          smallestBytes: target + 1,
          canTryGrayscale: !options.grayscaleToFit,
        ),
      );
    } catch (e) {
      return Left(PdfFailure(e.toString()));
    }
  }

  /// Marks a cached page render as just used, so the launch trim keeps it.
  static void _touch(String path) {
    try {
      File(path).setLastModifiedSync(DateTime.now());
    } on FileSystemException catch (_) {}
  }

  static const _baseQuality = 95;
  static const _pdfOverheadBase = 2048;
  static const _pdfOverheadPerPage = 1024;

  /// Final file names for the prepared files: `Name.pdf`, `Name.jpg` or
  /// `Name_1.jpg`, `Name_2.jpg`, …
  static List<String> finalNames(
    ScanDocument doc,
    ExportOptions options,
    int count,
  ) {
    final base =
        (options.fileName.isBlank ? doc.title : options.fileName).fileSafe;
    if (count == 1) return ['$base.${options.extension}'];
    return [
      for (var i = 0; i < count; i++) '${base}_${i + 1}.${options.extension}',
    ];
  }

  Future<Either<Failure, Unit>> deliver(
    ScanDocument doc,
    List<File> prepared,
    ExportOptions options,
    ExportTarget target, {
    StepTimer? timer,
  }) async {
    final List<File> files;
    try {
      final names = finalNames(doc, options, prepared.length);
      final dir = Directory(_files.exportPath('out_${doc.id}'));
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      files = [
        for (final (i, f) in prepared.indexed)
          await f.copy(p.join(dir.path, names[i])),
      ];
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
    timer?.lap('copy to final file name');

    final Either<Failure, Unit> result;
    if (target == ExportTarget.share) {
      // The sheet itself opens on the platform side; Dart only sees when the
      // user closes it, so the log stops here.
      timer
        ?..lap('open share sheet (request sent)')
        ..report();
      result = await _share.shareFiles(files, subject: doc.title);
    } else if (options.isImage) {
      result = await _save.saveImages(files);
    } else {
      result = (await _save.saveFileWithDialog(files.first)).map((_) => unit);
    }
    // The sheet or save has the files now (or was closed): free the space.
    await _files.discardExportFiles([
      for (final f in [...prepared, ...files]) f.path,
    ]);

    return result.fold(Left.new, (_) async {
      final type = target == ExportTarget.saveToPhone
          ? ActivityType.savedToPhone
          : options.isImage
          ? ActivityType.sharedImages
          : ActivityType.sharedPdf;
      await _repo.logActivity(doc.id, type);
      return const Right(unit);
    });
  }
}
