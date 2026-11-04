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
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// Renders the card sides at full quality, builds the sheet (image or PDF)
/// and shares / saves it.
@injectable
class BuildPrintLayout {
  BuildPrintLayout(this._render, this._pdf, this._sheet, this._files, this._share, this._save, this._repo);

  final PageRenderService _render;
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
  }) async {
    final pages = doc.sortedPages;
    if (pages.isEmpty) return const Left(NotFoundFailure());
    final frontPage = doc.pageOfSide(CardSide.front) ?? pages.first;
    final backPage = doc.pageOfSide(CardSide.back) ?? (pages.length > 1 ? pages[1] : null);
    final base = '${doc.title.fileSafe}_print';
    try {
      final front = await _render.renderForExport(
        frontPage,
        size: RenderSize.full,
        outputPath: _files.exportPath('print_${doc.id}/front.jpg'),
        jpegQuality: Limits.highJpegQuality,
      );
      String? back;
      if (backPage != null) {
        back = await _render.renderForExport(
          backPage,
          size: RenderSize.full,
          outputPath: _files.exportPath('print_${doc.id}/back.jpg'),
          jpegQuality: Limits.highJpegQuality,
        );
      }
      final spec = PrintLayoutSpec(
        kind: kind,
        output: output,
        copies: copies,
        frontPath: front,
        backPath: back,
        title: doc.title,
      );
      final File file;
      if (output == PrintOutput.image) {
        file = File(await _sheet.render(spec, outputPath: _files.exportPath('$base.jpg')));
      } else {
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
