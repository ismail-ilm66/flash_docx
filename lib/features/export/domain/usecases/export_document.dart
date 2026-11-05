import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/string_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
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

/// Renders pages at the chosen quality, builds the PDF or image set, then
/// shares or saves it. Progress is reported per page via `onProgress`.
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
      doc.mode.supportsPrintLayout && doc.pages.length >= 2 && o.layout == ExportLayout.oneImage;

  Future<Either<Failure, Unit>> call(
    ScanDocument doc,
    ExportOptions options,
    ExportTarget target, {
    void Function(double progress)? onProgress,
  }) async {
    final pages = doc.sortedPages;
    if (pages.isEmpty) return const Left(NotFoundFailure());
    final baseName = (options.fileName.isBlank ? doc.title : options.fileName).fileSafe;
    final size = options.quality == ExportQuality.high ? RenderSize.full : RenderSize.standard;
    final jpegQ = options.quality == ExportQuality.high
        ? Limits.highJpegQuality
        : Limits.standardJpegQuality;
    final imgExt = options.format == ExportFormat.png ? 'png' : 'jpg';

    final List<File> files;
    if (usesOneImage(doc, options)) {
      // Front above back at real size (P1-2), straight from the originals at
      // 300 DPI (Standard) or 600 DPI (High), encoded once.
      final kind = doc.mode == ScanMode.passport ? PrintKind.passport : PrintKind.idCard;
      final card = PrintLayoutCalculator.cardSize(kind);
      final dpi = BuildPrintLayout.dpiFor(options.quality);
      final front = doc.pageOfSide(CardSide.front) ?? pages[0];
      final back = doc.pageOfSide(CardSide.back) ?? pages[1];
      try {
        onProgress?.call(0.3);
        if (options.isImage) {
          final spec = PrintLayoutSpec(kind: kind, output: PrintOutput.image, copies: 1, frontPath: '', backPath: '', title: doc.title, cutGuides: false);
          files = [
            File(
              await _sheet.render(
                spec,
                front: (originalPath: front.originalPath, edits: front.edits),
                back: (originalPath: back.originalPath, edits: back.edits),
                dpi: dpi,
                jpegQuality: jpegQ,
                outputPath: _files.exportPath('$baseName.$imgExt'),
              ),
            ),
          ];
        } else {
          Future<String> side(ScanPage p, String name) => _processor.renderCard(
                p.originalPath,
                p.edits,
                widthMm: card.w,
                heightMm: card.h,
                dpi: dpi,
                outputPath: _files.exportPath('pdf_${doc.id}/$name.jpg'),
              );
          final spec = PrintLayoutSpec(
            kind: kind,
            output: PrintOutput.pdfOnePage,
            copies: 1,
            frontPath: await side(front, 'front'),
            backPath: await side(back, 'back'),
            title: doc.title,
            cutGuides: false,
          );
          files = [await _pdf.printSheet(spec, outputPath: _files.exportPath('$baseName.pdf'))];
        }
      } catch (e) {
        return Left(options.isImage ? ImageProcessingFailure(e.toString()) : PdfFailure(e.toString()));
      }
    } else {
      // Each page: rendered from the original, encoded once; a PDF embeds
      // those JPEGs as they are.
      final rendered = <String>[];
      try {
        for (final (i, page) in pages.indexed) {
          final name = options.isImage && pages.length > 1
              ? '${baseName}_${i + 1}.$imgExt'
              : options.isImage
                  ? '$baseName.$imgExt'
                  : 'page_${i + 1}.jpg';
          final out = await _render.renderForExport(
            page,
            size: size,
            outputPath: _files.exportPath(options.isImage ? name : 'pdf_${doc.id}/$name'),
            jpegQuality: jpegQ,
          );
          rendered.add(out);
          onProgress?.call((i + 1) / (pages.length + 1));
        }
      } catch (e) {
        return Left(ImageProcessingFailure(e.toString()));
      }
      if (options.isImage) {
        files = rendered.map(File.new).toList();
      } else {
        try {
          files = [
            await _pdf.fromPages(
              rendered,
              PdfOptions(pageSize: options.pageSize, title: doc.title),
              outputPath: _files.exportPath('$baseName.pdf'),
            ),
          ];
        } catch (e) {
          return Left(PdfFailure(e.toString()));
        }
      }
    }
    onProgress?.call(1);

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
