import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/string_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// Renders the card sides at full quality, builds the sheet (image or PDF)
/// and shares / saves it.
@injectable
class BuildPrintLayout {
  BuildPrintLayout(this._processor, this._pdf, this._sheet, this._files, this._share, this._save, this._repo);

  static int dpiFor(ExportQuality q) => q == ExportQuality.high ? 600 : 300;

  final ImageProcessor _processor;
  final PdfBuilder _pdf;
  final SheetImageRenderer _sheet;
  final FileStore _files;
  final ShareService _share;
  final SaveService _save;
  final DocumentRepository _repo;

  Future<Either<Failure, Unit>> call(
    ScanDocument doc, {
    required PrintKind kind,
    required PrintOutput output,
    required int copies,
    required ExportTarget target,
    bool cutGuides = true,
    bool swapSides = false,
    ExportQuality quality = ExportQuality.standard,
  }) async {
    final pages = doc.sortedPages;
    if (pages.isEmpty) return const Left(NotFoundFailure());
    var frontPage = doc.pageOfSide(CardSide.front) ?? pages.first;
    // Passports have no back side; ID cards use the back capture (or page 2).
    var backPage = kind == PrintKind.passport
        ? null
        : doc.pageOfSide(CardSide.back) ?? (pages.length > 1 ? pages[1] : null);
    if (swapSides && backPage != null) {
      (frontPage, backPage) = (backPage, frontPage);
    }
    final base = '${doc.title.fileSafe}_print';
    // P1-9: Standard = 300 DPI, High = 600 DPI (or the photo's own
    // resolution if lower). Always from the original photo, encoded once.
    final dpi = dpiFor(quality);
    final card = PrintLayoutCalculator.cardSize(kind);
    try {
      final File file;
      if (output == PrintOutput.image) {
        final spec = PrintLayoutSpec(kind: kind, output: output, copies: copies, frontPath: '', backPath: backPage == null ? null : '', title: doc.title);
        file = File(
          await _sheet.render(
            spec,
            front: (originalPath: frontPage.originalPath, edits: frontPage.edits),
            back: backPage == null ? null : (originalPath: backPage.originalPath, edits: backPage.edits),
            dpi: dpi,
            outputPath: _files.exportPath('$base.jpg'),
          ),
        );
      } else {
        Future<String> side(ScanPage p, String name) => _processor.renderCard(
              p.originalPath,
              p.edits,
              widthMm: card.w,
              heightMm: card.h,
              dpi: dpi,
              outputPath: _files.exportPath('print_${doc.id}/$name.jpg'),
            );
        final front = await side(frontPage, 'front');
        final back = backPage == null ? null : await side(backPage, 'back');
        final spec = PrintLayoutSpec(
          kind: kind,
          output: output,
          copies: copies,
          frontPath: front,
          backPath: back,
          title: doc.title,
          cutGuides: cutGuides,
        );
        file = await _pdf.printSheet(spec, outputPath: _files.exportPath('$base.pdf'));
      }
      final Either<Failure, Unit> r;
      if (target == ExportTarget.share) {
        r = await _share.shareFiles([file], subject: doc.title);
      } else if (output == PrintOutput.image) {
        r = await _save.saveImages([file]);
      } else {
        r = (await _save.saveFileWithDialog(file)).map((_) => unit);
      }
      return r.fold(Left.new, (_) async {
        await _repo.logActivity(doc.id, ActivityType.printLayout);
        return const Right(unit);
      });
    } catch (e) {
      return Left(output == PrintOutput.image ? ImageProcessingFailure(e.toString()) : PdfFailure(e.toString()));
    }
  }
}
