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
    void Function(int index, AutoEditsResult result)? onPrepared,
  }) async {
    final rules = ScanModeRules.of(mode);
    final filter = _defaultFilter;
    final pages = <ScanPage>[];
    try {
      for (final (i, src) in sourcePaths.indexed) {
        final id = newId();
        // The original is kept byte-for-byte (round 3, A2): moved for camera
        // shots, copied for imports. EXIF is applied whenever it is read.
        final original = _files.newCapturePath(id);
        if (copySource) {
          await File(src).copy(original);
        } else {
          try {
            await File(src).rename(original);
          } on FileSystemException {
            await File(src).copy(original);
            await File(src).delete().catchError((_) => File(src));
          }
        }
        final isCard = rules.aspectRatio != null;
        final auto = await _processor.ingest(
          original,
          previewOut: _files.basePreviewPath(id, original),
          snapAspectRatio: rules.aspectRatio,
          guide: fallbacks != null && i < fallbacks.length ? fallbacks[i] : null,
          outputAspect: rules.aspectRatio,
          // ID colour is the default for cards; documents use the Settings default.
          filter: isCard ? FilterType.idColor : filter,
        );
        pages.add(
          ScanPage(
            id: id,
            documentId: '',
            originalPath: original,
            edits: auto.edits,
            order: i,
            side: sides != null && i < sides.length ? sides[i] : null,
            edgesDetected: auto.detected,
          ),
        );
        onPrepared?.call(i, auto);
      }
      return Right(pages);
    } catch (e) {
      return Left(ImageProcessingFailure(e.toString()));
    }
  }
}
