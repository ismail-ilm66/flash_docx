import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/string_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flash_dox/features/print_layout/domain/usecases/build_print_layout.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

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

  /// Number of steps [prepare] reports through `onStep`.
  static int stepsFor(ScanDocument doc, ExportOptions o) =>
      usesOneImage(doc, o) ? 2 : doc.pages.length;

  /// Prepare then deliver, in one go.
  Future<Either<Failure, Unit>> call(
    ScanDocument doc,
    ExportOptions options,
    ExportTarget target,
  ) async {
    final r = await prepare(doc, options);
    return r.fold(
      (f) async => Left(f),
      (files) => deliver(doc, files, options, target),
    );
  }

  Future<Either<Failure, List<File>>> prepare(
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
          return Right([File(out)]);
        }
        Future<String> side(ScanPage pg, String name) => _processor.renderCard(
          pg.originalPath,
          pg.edits,
          widthMm: card.w,
          heightMm: card.h,
          dpi: dpi,
          outputPath: p.join(staging, '$name.jpg'),
        );
        final frontPath = await side(front, 'front');
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
        final pdf = await _pdf.printSheet(
          spec,
          outputPath: p.join(staging, 'doc.pdf'),
        );
        onStep?.call(total, total);
        return Right([pdf]);
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
    try {
      onStep?.call(0, total);
      for (final (i, page) in pages.indexed) {
        if (cancelled()) return const Left(CancelledFailure());
        if (options.format == ExportFormat.png) {
          rendered.add(
            await _render.renderForExport(
              page,
              size: size,
              outputPath: p.join(staging, 'page_${i + 1}.png'),
              jpegQuality: jpegQ,
            ),
          );
        } else {
          final cached = _files.exportPagePath(
            page.id,
            page.originalPath,
            page.edits,
            sizeKey: size.name,
            jpegQuality: jpegQ,
          );
          if (!File(cached).existsSync()) {
            // Written under a temp name and renamed, so a cancelled or failed
            // render never leaves half a JPEG in the cache.
            final tmp = '${p.withoutExtension(cached)}.part.jpg';
            await _render.renderForExport(
              page,
              size: size,
              outputPath: tmp,
              jpegQuality: jpegQ,
            );
            File(tmp).renameSync(cached);
          }
          rendered.add(cached);
        }
        onStep?.call(i + 1, total);
      }
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
    if (options.isImage) return Right(rendered.map(File.new).toList());
    if (cancelled()) return const Left(CancelledFailure());
    try {
      return Right([
        await _pdf.fromPages(
          rendered,
          PdfOptions(pageSize: options.pageSize, title: doc.title),
          outputPath: p.join(staging, 'doc.pdf'),
        ),
      ]);
    } catch (e) {
      return Left(PdfFailure(e.toString()));
    }
  }

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
    ExportTarget target,
  ) async {
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

    final Either<Failure, Unit> result;
    if (target == ExportTarget.share) {
      result = await _share.shareFiles(files, subject: doc.title);
    } else if (options.isImage) {
      result = await _save.saveImages(files);
    } else {
      result = (await _save.saveFileWithDialog(files.first)).map((_) => unit);
    }

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
