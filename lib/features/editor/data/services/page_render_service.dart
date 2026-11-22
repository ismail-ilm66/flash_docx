import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/clean_base_service.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Builds (and rebuilds) the processed / thumb caches of saved pages and
/// writes the paths back to the DB. Safe to call repeatedly: it skips pages
/// whose cache files already exist. Since round 6 (P0-2) pages are rendered
/// from their cleaned base ([CleanBaseService]), never cleaned again.
@lazySingleton
class PageRenderService {
  PageRenderService(this._processor, this._files, this._repo, this._bases);

  final ImageProcessor _processor;
  final FileStore _files;
  final DocumentRepository _repo;
  final CleanBaseService _bases;

  final Set<String> _inFlight = {};

  /// ID / passport pages are cleaned at the ID colour strength.
  static bool isCard(ScanMode m) => m == ScanMode.idCard || m == ScanMode.passport;

  /// Every page's display image and thumbnail, [first] (the page on
  /// screen) first, then the default Share pages.
  Future<void> ensureCaches(ScanDocument doc, {String? first}) async {
    final pages = [...doc.sortedPages]..sort((a, b) => (a.id == first ? 0 : 1).compareTo(b.id == first ? 0 : 1));
    for (final page in pages) {
      await ensurePageCache(page, card: isCard(doc.mode));
    }
    await warmExportPages(doc);
  }

  /// Round 10, P0-3: documents whose display images are missing (made
  /// before this update, or after the cache was cleared) get them in the
  /// background, most recent first, so opening one never waits.
  Future<void> ensureAllCaches() async {
    final docs = await _repo.watchAll().first;
    for (final doc in docs) {
      final missing = doc.pages.any((p) => !_hasCaches(p));
      if (!missing) continue;
      try {
        await ensureCaches(doc);
      } catch (e) {
        debugPrint('[cache] ${doc.id}: $e');
      }
    }
  }

  static bool _hasCaches(ScanPage p) =>
      p.processedPath != null && File(p.processedPath!).existsSync() && p.thumbPath != null && File(p.thumbPath!).existsSync();

  /// Warm-up renders queued or running, by output path.
  final _warming = <String, ({CancelToken cancel, Future<void> done})>{};

  /// The page JPEGs the default Share (standard quality) embeds, made in the
  /// background once the viewer caches are done: the first Share after a
  /// scan, an edit or a relaunch then only builds the PDF. Documents only
  /// (ID card / passport exports render the card instead).
  Future<void> warmExportPages(ScanDocument doc) async {
    if (doc.mode != ScanMode.document) return;
    for (final page in doc.sortedPages) {
      final out = _files.exportPagePath(
        doc.id,
        page.id,
        page.originalPath,
        page.edits,
        sizeKey: RenderSize.standard.name,
        jpegQuality: Limits.standardJpegQuality,
      );
      if (File(out).existsSync() || _warming.containsKey(out)) continue;
      final cancel = CancelToken();
      final done = Completer<void>();
      _warming[out] = (cancel: cancel, done: done.future);
      try {
        // Its own temp name: a Share rendering the same page meanwhile
        // writes `.part.jpg`.
        final tmp = '${p.withoutExtension(out)}.warm.jpg';
        await renderExportPage(
          page,
          size: RenderSize.standard,
          outputPath: tmp,
          jpegQuality: Limits.standardJpegQuality,
          card: false,
          priority: JobPriority.background,
          cancel: cancel,
        );
        if (!File(out).existsSync()) File(tmp).renameSync(out);
        await _files.pruneExportPages(doc.id, page.id, RenderSize.standard.name, keep: out);
      } on JobCancelled {
        // A Share took this page over before the render started.
      } on Object catch (e) {
        debugPrint('[export] warm ${page.id}: $e');
      } finally {
        _warming.remove(out);
        done.complete();
      }
    }
  }

  /// A Share needs the export JPEG at [out] now. A warm-up render of it that
  /// is still queued is dropped (the caller renders it on the interactive
  /// lane instead); one already running is awaited, not done twice (on a
  /// Kirin 710 that's 13 s per page). True when [out] exists afterwards.
  Future<bool> joinWarm(String out) async {
    final w = _warming[out];
    if (w != null) {
      w.cancel.cancel();
      await w.done;
    }
    return File(out).existsSync();
  }

  /// Re-reads the document so cache writes never clobber persisted fields
  /// (order, side) with values from in-memory drafts.
  Future<void> ensureCachesFor(String documentId) async {
    final r = await _repo.get(documentId);
    final doc = r.getOrElse((_) => throw StateError('document $documentId not found'));
    await ensureCaches(doc);
  }

  Future<ScanPage> ensurePageCache(ScanPage page, {bool card = false}) async {
    if (_inFlight.contains(page.id)) return page;
    if (_hasCaches(page)) return page;
    _inFlight.add(page.id);
    try {
      // Preview and thumbnail come from one decode, written under fresh file
      // names so the UI can't show a stale image and nothing needs evicting.
      final paths = _files.newCachePaths(page.documentId, page.id);
      // Round 10, P0-3: the display image is the finished page at 1600 px.
      // From the cleaned base when the editor already made it (only the
      // filter runs), else Enhance's look (1200 px, already filtered), else
      // a fresh base.
      final look = _files.lookPath(page.id, page.originalPath, page.edits);
      final covered = CleanBaseService.covers(page.edits);
      final base = covered ? _bases.basePath(page, card: card) : null;
      if (base != null && File(base).existsSync()) {
        await _displayFrom(base, page, paths.processed);
        await _thumbFrom(paths.processed, paths.thumb);
      } else if (PreviewCache.lookCovers(page.edits) && File(look).existsSync()) {
        // Enhance already made this exact page at preview size: copy it and
        // shrink it for the thumbnail, instead of filtering the original
        // again (5 s on a Kirin 710).
        await File(paths.processed).parent.create(recursive: true);
        await File(look).copy(paths.processed);
        await _thumbFrom(paths.processed, paths.thumb);
      } else if (covered) {
        // From the cleaned base (made if this page has none yet).
        await _displayFrom(await _bases.ensure(page, card: card), page, paths.processed);
        await _thumbFrom(paths.processed, paths.thumb);
      } else {
        await _processor.renderPageCaches(
          page.originalPath,
          page.edits,
          processedOut: paths.processed,
          thumbOut: paths.thumb,
        );
      }
      final updated = page.copyWith(processedPath: paths.processed, thumbPath: paths.thumb);
      await _repo.updatePage(updated);
      await _files.pruneCaches(page.documentId, page.id, keep: {paths.processed, paths.thumb});
      return updated;
    } finally {
      _inFlight.remove(page.id);
    }
  }

  Future<void> _displayFrom(String base, ScanPage page, String out) => _processor.renderFromClean(
    base,
    page.edits,
    outputPath: out,
    maxLongEdge: RenderPx.displayLongEdge,
    jpegQuality: Limits.displayJpegQuality,
    priority: JobPriority.background,
  );

  /// The thumbnail from an already filtered page image: just shrunk.
  Future<void> _thumbFrom(String processed, String thumb) => _processor.render(
    processed,
    const PageEdits(filter: FilterType.original),
    size: RenderSize.thumb,
    outputPath: thumb,
    jpegQuality: Limits.thumbJpegQuality,
  );

  /// An export page at [size] (round 6, P0-2): from the page's cleaned base,
  /// waiting for it if it's being made (a Share moves it up the queue);
  /// `original` and passport photos straight from the original. High uses
  /// the 2400 px base (2000 on a low-RAM phone).
  Future<String> renderExportPage(
    ScanPage page, {
    required RenderSize size,
    required String outputPath,
    required int jpegQuality,
    required bool card,
    JobPriority priority = JobPriority.interactive,
    CancelToken? cancel,
  }) async {
    if (!CleanBaseService.covers(page.edits)) {
      return renderForExport(
        page,
        size: size,
        outputPath: outputPath,
        jpegQuality: jpegQuality,
        priority: priority,
        cancel: cancel,
      );
    }
    final high = size.longEdge == null;
    final base = await _bases.ensure(
      page,
      card: card,
      longEdge: _bases.longEdgeFor(high: high ? true : null),
      priority: priority,
    );
    return _processor.renderFromClean(
      base,
      page.edits,
      outputPath: outputPath,
      maxLongEdge: size.longEdge,
      jpegQuality: jpegQuality,
      priority: priority,
      cancel: cancel,
    );
  }

  /// An ID card / passport side at real size for [dpi], from its cleaned
  /// base (2400 px for 600 DPI).
  Future<String> renderCardSide(
    ScanPage page, {
    required double widthMm,
    required double heightMm,
    required int dpi,
    required String outputPath,
  }) async {
    if (!CleanBaseService.covers(page.edits)) {
      return _processor.renderCard(
        page.originalPath,
        page.edits,
        widthMm: widthMm,
        heightMm: heightMm,
        dpi: dpi,
        outputPath: outputPath,
      );
    }
    final base = await _bases.ensure(
      page,
      card: true,
      longEdge: _bases.longEdgeFor(high: dpi >= 600 ? true : null),
      priority: JobPriority.interactive,
    );
    return _processor.renderCardFromClean(
      base,
      page.edits,
      widthMm: widthMm,
      heightMm: heightMm,
      dpi: dpi,
      outputPath: outputPath,
    );
  }

  /// Renders a page at export resolution to [outputPath]. Interactive lane
  /// by default: someone is waiting on the share sheet, so it goes ahead of
  /// the viewer's background caches.
  Future<String> renderForExport(
    ScanPage page, {
    required RenderSize size,
    required String outputPath,
    required int jpegQuality,
    JobPriority priority = JobPriority.interactive,
    CancelToken? cancel,
  }) {
    return _processor.render(
      page.originalPath,
      page.edits,
      size: size,
      outputPath: outputPath,
      jpegQuality: jpegQuality,
      priority: priority,
      cancel: cancel,
    );
  }
}
