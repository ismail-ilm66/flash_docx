import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/ocr/domain/text_recognizer.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

/// The one pipeline every image goes through, whatever its source (camera,
/// Photos, Files, share-in): upright (EXIF) → edge detection → default
/// filter from Settings → draft [ScanPage] ready for Adjust edges.
@injectable
class PreparePages {
  PreparePages(this._processor, this._files, this._prefs, this._ocr);

  final ImageProcessor _processor;
  final FileStore _files;
  final PrefsService _prefs;
  final TextRecognizer _ocr;

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
    List<int>? turns,
    List<String>? ids,
    bool copySource = true,
    void Function(int index, AutoEditsResult result)? onPrepared,
  }) async {
    final rules = ScanModeRules.of(mode);
    final filter = _defaultFilter;
    final pages = <ScanPage>[];
    try {
      for (final (i, src) in sourcePaths.indexed) {
        final given = ids != null && i < ids.length ? ids[i] : null;
        final id = given ?? newId();
        // The original is kept byte-for-byte (round 3, A2) unless it needs
        // turning upright (P0-1): moved for camera shots, copied for
        // imports. A retake keeps the page id but gets a fresh file, so the
        // photo it replaces is never overwritten.
        final original = _files.newCapturePath(given == null ? id : '${id}_${DateTime.now().microsecondsSinceEpoch}');
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
          extraTurns: turns != null && i < turns.length ? turns[i] : 0,
        );
        var edits = auto.edits;
        if (isCard) {
          edits = edits.copyWith(
            quarterTurns: await _cardTurns(id, original, edits, auto),
          );
        }
        pages.add(
          ScanPage(
            id: id,
            documentId: '',
            originalPath: original,
            edits: edits,
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

  /// P0-1: ID / passport cards end up landscape and the right way up.
  /// Portrait warps turn to landscape; then 0° vs 180° is decided by which
  /// way ML Kit reads more characters on a 640 px render of the preview.
  /// Ties keep 0°. The result is plain `quarterTurns`, so the user can still
  /// rotate by hand.
  Future<int> _cardTurns(String id, String original, PageEdits edits, AutoEditsResult auto) async {
    final crop = edits.crop;
    final w = auto.width;
    final h = auto.height;
    var base = 0;
    if (crop != null && w != null && h != null && crop.avgWidth * w < crop.avgHeight * h) {
      base = 1;
    }
    final preview = _files.basePreviewPath(id, original);
    try {
      Future<int> score(int t) async {
        final out = await _processor.render(
          preview,
          edits.copyWith(quarterTurns: t, filter: FilterType.original),
          size: RenderSize.probe,
          outputPath: _files.newCapturePath('probe_${id}_$t'),
          jpegQuality: 85,
        );
        final text = (await _ocr.read(out)).getOrElse((_) => '');
        unawaited(File(out).delete().catchError((_) => File(out)));
        return RegExp('[A-Za-z0-9]').allMatches(text).length;
      }

      final up = await score(base);
      final flipped = await score(base + 2);
      return flipped > up ? base + 2 : base;
    } catch (e) {
      debugPrint('[ingest] card orientation check failed: $e');
      return base;
    }
  }
}
