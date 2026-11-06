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

  /// [quick] if it already exists on disk, else null (no render started).
  String? quickIfReady(ScanPage page) {
    final path = _files.quickPath(page.id, page.originalPath, page.edits);
    return File(path).existsSync() ? path : null;
  }
}
