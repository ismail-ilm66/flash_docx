import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/scanner/domain/capture_orientation_log.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
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
    List<CaptureMeta?>? captures,
    List<Quad?>? lives,
    List<Object?>? perfPages,
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
        final original = _files.newOriginalPath(given == null ? id : '${id}_${DateTime.now().microsecondsSinceEpoch}');
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
          capture: captures != null && i < captures.length ? captures[i] : null,
          live: lives != null && i < lives.length ? lives[i] : null,
          perfPage: perfPages != null && i < perfPages.length ? perfPages[i] : null,
        );
        if (auto.orientation != null) CaptureOrientationLog.record(id, auto.orientation!);
        var edits = auto.edits;
        // Round 11, P1-6: "Auto crop" off: a Document camera shot starts on
        // Adjust edges with the whole photo.
        final camera = captures != null && i < captures.length && captures[i] != null;
        if (camera && !isCard && !_prefs.autoCrop) edits = edits.copyWith(crop: Quad.full());
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

  /// Round 11b, P0-18 / P0-19: the same pipeline, one image at a time, so
  /// Adjust edges can open at once and show each page as it's ready. A page
  /// that can't be read comes back null.
  List<Future<ScanPage?>> oneByOne(List<String> sourcePaths, {required ScanMode mode, bool copySource = true}) {
    var chain = Future<void>.value();
    return [
      for (final (i, src) in sourcePaths.indexed)
        () {
          final done = Completer<ScanPage?>();
          chain = chain.then((_) async {
            final r = await call([src], mode: mode, copySource: copySource);
            done.complete(r.fold((_) => null, (pages) => pages.single.copyWith(order: i)));
          });
          return done.future;
        }(),
    ];
  }

  /// P0-1: ID / passport cards end up landscape. Round 11c: text
  /// recognition never runs while scanning, so 0° vs 180° is no longer
  /// guessed by reading the card; the user turns an upside-down card.
  Future<int> _cardTurns(String id, String original, PageEdits edits, AutoEditsResult auto) async {
    final crop = edits.crop;
    final w = auto.width;
    final h = auto.height;
    return crop != null && w != null && h != null && crop.avgWidth * w < crop.avgHeight * h ? 1 : 0;
  }

}
