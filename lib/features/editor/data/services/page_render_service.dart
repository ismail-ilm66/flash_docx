import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter/painting.dart';
import 'package:injectable/injectable.dart';

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
  }

  Future<ScanPage> ensurePageCache(ScanPage page) async {
    if (_inFlight.contains(page.id)) return page;
    final hasProcessed =
        page.processedPath != null && File(page.processedPath!).existsSync();
    final hasThumb = page.thumbPath != null && File(page.thumbPath!).existsSync();
    if (hasProcessed && hasThumb) return page;
    _inFlight.add(page.id);
    try {
      var updated = page;
      if (!hasProcessed) {
        final out = await _processor.render(
          page.originalPath,
          page.edits,
          size: RenderSize.preview,
          outputPath: _files.processedPath(page.documentId, page.id),
          jpegQuality: Limits.cacheJpegQuality,
        );
        updated = updated.copyWith(processedPath: out);
        await _evict(out);
      }
      if (!hasThumb) {
        final out = await _processor.render(
          page.originalPath,
          page.edits,
          size: RenderSize.thumb,
          outputPath: _files.thumbPath(page.documentId, page.id),
          jpegQuality: 80,
        );
        updated = updated.copyWith(thumbPath: out);
        await _evict(out);
      }
      await _repo.updatePage(updated);
      return updated;
    } finally {
      _inFlight.remove(page.id);
    }
  }

  /// Cache files are rewritten in place, so Flutter's in-memory image cache
  /// must forget the old bytes or the UI keeps showing the previous render.
  Future<void> _evict(String path) async {
    final file = File(path);
    await FileImage(file).evict();
    // Thumbnails are decoded through ResizeImage; evicting the base provider
    // doesn't reach those entries, so drop the whole (small) cache.
    PaintingBinding.instance.imageCache.clear();
  }

  /// Renders a page at export resolution to [outputPath].
  Future<String> renderForExport(
    ScanPage page, {
    required RenderSize size,
    required String outputPath,
    required int jpegQuality,
  }) {
    return _processor.render(
      page.originalPath,
      page.edits,
      size: size,
      outputPath: outputPath,
      jpegQuality: jpegQuality,
    );
  }
}
