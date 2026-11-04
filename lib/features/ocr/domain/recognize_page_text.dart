import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/ocr/domain/text_recognizer.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// Reads text from the *processed* page (better accuracy than the raw photo),
/// caching the result on the page. Cleared automatically when edits change
/// (see `ScanPage.withEdits`).
@injectable
class RecognizePageText {
  RecognizePageText(this._ocr, this._render, this._repo);

  final TextRecognizer _ocr;
  final PageRenderService _render;
  final DocumentRepository _repo;

  Future<Either<Failure, String>> call(ScanPage page, {bool force = false}) async {
    if (!force && page.ocrText != null) return Right(page.ocrText!);
    final ScanPage ready;
    try {
      ready = await _render.ensurePageCache(page);
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
    final r = await _ocr.read(ready.processedPath ?? ready.originalPath);
    return r.fold(Left.new, (text) async {
      await _repo.updatePage(ready.copyWith(ocrText: text));
      return Right(text);
    });
  }
}
