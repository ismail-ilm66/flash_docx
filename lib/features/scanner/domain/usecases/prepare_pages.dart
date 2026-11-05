import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// The one pipeline every image goes through, whatever its source (camera,
/// Photos, Files, share-in): upright (EXIF) → edge detection → default
/// filter from Settings → draft [ScanPage] ready for Adjust edges.
@injectable
class PreparePages {
  PreparePages(this._processor, this._files, this._prefs);

  final ImageProcessor _processor;
  final FileStore _files;
  final PrefsService _prefs;

  FilterType get _defaultFilter =>
      FilterType.values.where((f) => f.name == _prefs.defaultFilter).firstOrNull ??
      FilterType.auto;

  /// [fallbacks] are per-image crops to use when nothing is detected (the
  /// camera's on-screen guide frame in ID / passport modes).
  Future<Either<Failure, List<ScanPage>>> call(
    List<String> sourcePaths, {
    required ScanMode mode,
    List<CardSide?>? sides,
    List<Quad?>? fallbacks,
    bool copySource = true,
  }) async {
    final rules = ScanModeRules.of(mode);
    final filter = _defaultFilter;
    final pages = <ScanPage>[];
    try {
      for (final (i, src) in sourcePaths.indexed) {
        final id = newId();
        final upright = _files.newCapturePath(id);
        // One decode: upright original + editor preview + edge detection.
        final auto = await _processor.ingest(
          src,
          originalOut: upright,
          previewOut: _files.basePreviewPath(id, upright),
          snapAspectRatio: rules.aspectRatio,
          fallback: fallbacks != null && i < fallbacks.length ? fallbacks[i] : null,
          filter: filter,
        );
        if (!copySource) {
          final f = File(src);
          if (f.existsSync()) await f.delete();
        }
        pages.add(
          ScanPage(
            id: id,
            documentId: '',
            originalPath: upright,
            edits: auto.edits,
            order: i,
            side: sides != null && i < sides.length ? sides[i] : null,
            edgesDetected: auto.detected,
          ),
        );
      }
      return Right(pages);
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
  }
}
