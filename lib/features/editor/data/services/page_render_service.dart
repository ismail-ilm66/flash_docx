import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Builds (and rebuilds) the processed / thumb caches of saved pages and
/// writes the paths back to the DB. Safe to call repeatedly: it skips pages
/// whose cache files already exist.
@lazySingleton
class PageRenderService {
  PageRenderService(this._processor, this._files, this._repo);

  final ImageProcessor _processor;
  final FileStore _files;
  final DocumentRepository _repo;

  final Set<String> _inFlight = {};

  Future<void> ensureCaches(ScanDocument doc) async {
    for (final page in doc.pages) {
      await ensurePageCache(page);
    }
    await warmExportPages(doc);
  }

  final Set<String> _warming = {};

  /// The page JPEGs the default Share (standard quality) embeds, made in the
  /// background once the viewer caches are done: the first Share after a
  /// scan, an edit or a relaunch then only builds the PDF. Documents only
  /// (ID card / passport exports render the card instead).
  Future<void> warmExportPages(ScanDocument doc) async {
    if (doc.mode != ScanMode.document) return;
    for (final page in doc.sortedPages) {
      final out = _files.exportPagePath(
        page.id,
        page.originalPath,
        page.edits,
        sizeKey: RenderSize.standard.name,
        jpegQuality: Limits.standardJpegQuality,
      );
      if (File(out).existsSync() || !_warming.add(out)) continue;
      try {
        // Its own temp name: a Share rendering the same page meanwhile
        // writes `.part.jpg`.
        final tmp = '${p.withoutExtension(out)}.warm.jpg';
        await renderForExport(
          page,
          size: RenderSize.standard,
          outputPath: tmp,
          jpegQuality: Limits.standardJpegQuality,
          priority: JobPriority.background,
        );
        if (!File(out).existsSync()) File(tmp).renameSync(out);
      } on Object catch (e) {
        debugPrint('[export] warm ${page.id}: $e');
      } finally {
        _warming.remove(out);
      }
    }
  }

  /// Re-reads the document so cache writes never clobber persisted fields
  /// (order, side) with values from in-memory drafts.
  Future<void> ensureCachesFor(String documentId) async {
    final r = await _repo.get(documentId);
    final doc = r.getOrElse((_) => throw StateError('document $documentId not found'));
    await ensureCaches(doc);
  }

  Future<ScanPage> ensurePageCache(ScanPage page) async {
    if (_inFlight.contains(page.id)) return page;
    final hasProcessed =
        page.processedPath != null && File(page.processedPath!).existsSync();
    final hasThumb = page.thumbPath != null && File(page.thumbPath!).existsSync();
    if (hasProcessed && hasThumb) return page;
    _inFlight.add(page.id);
    try {
      // Preview and thumbnail come from one decode, written under fresh file
      // names so the UI can't show a stale image and nothing needs evicting.
      final paths = _files.newCachePaths(page.documentId, page.id);
      await _processor.renderPageCaches(
        page.originalPath,
        page.edits,
        processedOut: paths.processed,
        thumbOut: paths.thumb,
      );
      final updated = page.copyWith(processedPath: paths.processed, thumbPath: paths.thumb);
      await _repo.updatePage(updated);
      await _files.pruneCaches(page.documentId, page.id, keep: {paths.processed, paths.thumb});
      return updated;
    } finally {
      _inFlight.remove(page.id);
    }
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
  }) {
    return _processor.render(
      page.originalPath,
      page.edits,
      size: size,
      outputPath: outputPath,
      jpegQuality: jpegQuality,
      priority: priority,
    );
  }
}
