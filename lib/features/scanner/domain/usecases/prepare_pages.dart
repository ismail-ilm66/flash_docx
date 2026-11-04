import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// Raw capture or imported image → upright copy in the capture folder →
/// auto edits → draft [ScanPage]. Works for both camera and import.
@injectable
class PreparePages {
  PreparePages(this._processor, this._files);

  final ImageProcessor _processor;
  final FileStore _files;

  Future<Either<Failure, List<ScanPage>>> call(
    List<String> sourcePaths, {
    required ScanMode mode,
    List<CardSide?>? sides,
    bool copySource = true,
  }) async {
    final rules = ScanModeRules.of(mode);
    final pages = <ScanPage>[];
    try {
      for (final (i, src) in sourcePaths.indexed) {
        final id = newId();
        final upright = _files.newCapturePath(id);
        await _processor.normalizeOrientation(src, outputPath: upright);
        if (!copySource) {
          final f = File(src);
          if (f.existsSync()) await f.delete();
        }
        final edits = await _processor.autoEdits(
          upright,
          snapAspectRatio: rules.aspectRatio,
        );
        pages.add(
          ScanPage(
            id: id,
            documentId: '',
            originalPath: upright,
            edits: edits,
            order: i,
            side: sides != null && i < sides.length ? sides[i] : null,
          ),
        );
      }
      return Right(pages);
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
  }
}
