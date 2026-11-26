import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

/// What a page shows while its real preview is being made (round 4, P0-4):
/// the last preview it showed, else a fast crop-only render — never the
/// uncropped photo.
///
/// Files live in the capture temp folder (keyed by crop and rotation, so a
/// re-crop gets a new one); this class remembers the last shown file per
/// page in a small LRU.
@lazySingleton
class PreviewCache {
  PreviewCache(this._processor, this._files);

  final ImageProcessor _processor;
  final FileStore _files;

  static const int _maxRemembered = 64;
  final _last = <String, String>{}; // insertion-ordered: an LRU
  final _inFlight = <String, Future<String>>{};

  /// The last preview this page showed, if its file still exists.
  String? last(String pageId) {
    final path = _last[pageId];
    if (path == null) return null;
    if (!File(path).existsSync()) {
      _last.remove(pageId);
      return null;
    }
    return path;
  }

  void remember(String pageId, String path) {
    _last
      ..remove(pageId)
      ..[pageId] = path;
    while (_last.length > _maxRemembered) {
      _last.remove(_last.keys.first);
    }
  }

  /// Round 11, P0-7: the images Enhance showed, handed to the viewer on
  /// Done (page id → the edits they show, and the file).
  final _handedOff = <String, (PageEdits, String)>{};

  void handOff(String pageId, PageEdits edits, String path) => _handedOff[pageId] = (edits, path);

  /// What Enhance showed for exactly [page]'s look, if the file still exists.
  String? handedOff(ScanPage page) {
    final h = _handedOff[page.id];
    if (h == null || h.$1 != page.edits || !File(h.$2).existsSync()) return null;
    return h.$2;
  }

  /// The quick crop-only preview (600 px, no filter) for [page]; rendered on
  /// the interactive lane the first time.
  Future<String> quick(ScanPage page) {
    final path = _files.quickPath(page.id, page.originalPath, page.edits);
    if (File(path).existsSync()) return Future.value(path);
    return _inFlight[path] ??= () async {
      final sw = Stopwatch()..start();
      try {
        final out = await _processor.renderQuick(page.originalPath, page.edits, outputPath: path);
        debugPrint('[perf] quick preview ${page.id} in ${sw.elapsedMilliseconds} ms');
        return out;
      } finally {
        _inFlight.remove(path)?.ignore();
      }
    }();
  }

  /// The Enhance preview made for exactly this look, if it's still on disk:
  /// right after Done it's the best stand-in for the viewer's processed page.
  /// Null when the page has things that preview leaves out (sliders,
  /// signatures, a passport photo's finish).
  String? lookIfReady(ScanPage page) {
    if (!lookCovers(page.edits)) return null;
    final path = _files.lookPath(page.id, page.originalPath, page.edits);
    return File(path).existsSync() ? path : null;
  }

  /// True when the Enhance look for [e] is the whole page: it leaves out
  /// sliders, signatures and a passport photo's finish.
  static bool lookCovers(PageEdits e) =>
      !e.hasSliders &&
      e.overlays.isEmpty &&
      e.photoWidthMm == null &&
      e.photoBackground == PhotoBackground.original &&
      e.photoEnhance == PhotoEnhance.off;
}
