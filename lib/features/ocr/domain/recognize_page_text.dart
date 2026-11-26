import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/ocr/domain/text_recognizer.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// Reads text from a dedicated OCR image: the page cropped and
/// perspective-corrected at full resolution, gray, mildly contrast-stretched
/// and denoised. The user's filter and sliders are never used, so the result
/// is the same whichever look they picked.
///
/// The OCR image is cached per page and keyed by crop + rotation, so a new
/// crop invalidates it; the text itself is cached on the page.
@injectable
class RecognizePageText {
  RecognizePageText(this._ocr, this._processor, this._files, this._repo);

  final TextRecognizer _ocr;
  final ImageProcessor _processor;
  final FileStore _files;
  final DocumentRepository _repo;

  /// Round 11b: the OCR image is now the Auto page (version 2).
  static int cropKey(PageEdits e) => Object.hash(e.geometryKey, 2);

  Future<Either<Failure, String>> call(ScanPage page, {bool force = false}) async {
    if (!force && page.ocrText != null) return Right(joinParagraphs(page.ocrText!));
    // The caller may hold a stale snapshot; check the stored page first.
    final fresh = (await _repo.get(page.documentId))
        .toOption()
        .toNullable()
        ?.pages
        .where((p) => p.id == page.id)
        .firstOrNull;
    final current = fresh ?? page;
    if (!force && current.ocrText != null) return Right(joinParagraphs(current.ocrText!));

    final String ocrImage;
    try {
      final target = _files.ocrPath(current.documentId, current.id, cropKey(current.edits));
      if (File(target).existsSync()) {
        ocrImage = target;
      } else {
        ocrImage = await _processor.renderForOcr(
          current.originalPath,
          current.edits,
          outputPath: target,
        );
        await _files.pruneOcrImages(current.documentId, current.id, keep: target);
      }
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }

    final r = await _ocr.read(ocrImage);
    return r.fold(Left.new, (raw) async {
      final text = joinParagraphs(raw);
      await _repo.updatePage(current.copyWith(ocrText: text));
      return Right(text);
    });
  }

  /// Round 11b, K2: lines joined into paragraphs. A line ending in "-" is
  /// joined to the next without the hyphen; a line that doesn't end with
  /// `. : ? !`, followed by one starting with a lower-case letter, is
  /// joined with a space. Empty lines between blocks stay.
  static String joinParagraphs(String text) {
    final out = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (out.isNotEmpty && out.last.isNotEmpty && line.isNotEmpty) {
        final prev = out.last;
        final first = line.trimLeft();
        if (prev.endsWith('-') && prev.length > 1 && RegExp(r'[A-Za-z]$').hasMatch(prev.substring(0, prev.length - 1))) {
          out[out.length - 1] = prev.substring(0, prev.length - 1) + first;
          continue;
        }
        if (!RegExp(r'[.:?!]$').hasMatch(prev) && RegExp('^[a-z]').hasMatch(first)) {
          out[out.length - 1] = '$prev $first';
          continue;
        }
      }
      out.add(line);
    }
    return out.join('\n');
  }
}
