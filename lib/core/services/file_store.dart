import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the on-disk layout:
///
/// ```text
/// <app documents>/flashdox/docs/<docId>/original/<pageId>.jpg
/// <app documents>/flashdox/docs/<docId>/processed/<pageId>.jpg   # cache
/// <app documents>/flashdox/docs/<docId>/thumb/<pageId>.jpg       # cache
/// <temp>/flashdox_export/                                        # cleared on launch
/// <temp>/flashdox_capture/                                       # raw camera shots awaiting a document
/// ```
@lazySingleton
class FileStore {
  late final Directory _root;
  late final Directory _exportTemp;
  late final Directory _captureTemp;

  Directory get root => _root;
  Directory get exportTemp => _exportTemp;
  Directory get captureTemp => _captureTemp;

  @PostConstruct(preResolve: true)
  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();
    _root = Directory(p.join(docs.path, 'flashdox'));
    _exportTemp = Directory(p.join(tmp.path, 'flashdox_export'));
    _captureTemp = Directory(p.join(tmp.path, 'flashdox_capture'));
    await Future.wait([
      Directory(p.join(_root.path, 'docs')).create(recursive: true),
      _exportTemp.create(recursive: true),
      _captureTemp.create(recursive: true),
    ]);
  }

  Directory docDir(String docId) => Directory(p.join(_root.path, 'docs', docId));

  String originalPath(String docId, String pageId) =>
      p.join(docDir(docId).path, 'original', '$pageId.jpg');
  String processedPath(String docId, String pageId) =>
      p.join(docDir(docId).path, 'processed', '$pageId.jpg');
  String thumbPath(String docId, String pageId) =>
      p.join(docDir(docId).path, 'thumb', '$pageId.jpg');

  /// OCR image cache, keyed by the crop/rotation so a new crop invalidates it.
  String ocrPath(String docId, String pageId, int cropKey) =>
      p.join(docDir(docId).path, 'processed', '${pageId}_ocr_$cropKey.jpg');

  /// Removes stale OCR images for [pageId] other than [keep].
  Future<void> pruneOcrImages(String docId, String pageId, {String? keep}) async {
    final dir = Directory(p.join(docDir(docId).path, 'processed'));
    if (!dir.existsSync()) return;
    await for (final f in dir.list()) {
      if (f is File && p.basename(f.path).startsWith('${pageId}_ocr_') && f.path != keep) {
        await f.delete();
      }
    }
  }

  /// Editor base preview (upright, uncropped, preview size) for a page. Keyed
  /// by the original's path so a retake or a moved original gets a new one.
  String basePreviewPath(String pageId, String originalPath) =>
      p.join(_captureTemp.path, 'base_${pageId}_${_stamp(originalPath)}.jpg');

  /// Cropped + rotated page at preview size, reused while switching filters.
  String workPath(String pageId, String originalPath, PageEdits edits) => p.join(
        _captureTemp.path,
        'work_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns)}.jpg',
      );

  /// Enhance preview for one filter (sliders are applied live, not baked).
  String lookPath(String pageId, String originalPath, PageEdits edits) => p.join(
        _captureTemp.path,
        'look_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.filter)}.jpg',
      );

  /// Identifies one version of an original: its path plus modification time,
  /// so a retake saved over the same path still gets fresh previews.
  int _stamp(String originalPath) {
    final f = File(originalPath);
    final mtime = f.existsSync() ? f.lastModifiedSync().microsecondsSinceEpoch : 0;
    return Object.hash(originalPath, mtime);
  }

  /// True when [path] already lives inside the document's folder.
  bool isInDoc(String docId, String path) => p.isWithin(docDir(docId).path, path);

  /// New, never-before-used file names for a page's viewer caches. A fresh
  /// name means Flutter's image cache can never show a stale render, so
  /// nothing has to be evicted. Old versions are removed by [pruneCaches].
  ({String processed, String thumb}) newCachePaths(String docId, String pageId) {
    final v = DateTime.now().microsecondsSinceEpoch;
    return (
      processed: p.join(docDir(docId).path, 'processed', '${pageId}_v$v.jpg'),
      thumb: p.join(docDir(docId).path, 'thumb', '${pageId}_v$v.jpg'),
    );
  }

  /// Deletes a page's cache files except [keep] (legacy fixed names too).
  Future<void> pruneCaches(String docId, String pageId, {Set<String> keep = const {}}) async {
    for (final sub in ['processed', 'thumb']) {
      final dir = Directory(p.join(docDir(docId).path, sub));
      if (!dir.existsSync()) continue;
      await for (final f in dir.list()) {
        if (f is! File || keep.contains(f.path)) continue;
        final name = p.basename(f.path);
        if (name == '$pageId.jpg' || name.startsWith('${pageId}_v')) {
          await f.delete().catchError((_) => f);
        }
      }
    }
  }

  /// A fresh path for a raw capture / import before it belongs to a document.
  String newCapturePath(String id) => p.join(_captureTemp.path, '$id.jpg');

  String exportPath(String fileName) => p.join(_exportTemp.path, fileName);

  Future<void> ensureDocDirs(String docId) async {
    final d = docDir(docId);
    await Future.wait([
      Directory(p.join(d.path, 'original')).create(recursive: true),
      Directory(p.join(d.path, 'processed')).create(recursive: true),
      Directory(p.join(d.path, 'thumb')).create(recursive: true),
    ]);
  }

  /// Moves a capture into a document's `original` folder. Falls back to copy
  /// when a rename across filesystems fails.
  Future<String> adoptOriginal({
    required String sourcePath,
    required String docId,
    required String pageId,
  }) async {
    await ensureDocDirs(docId);
    final target = originalPath(docId, pageId);
    final src = File(sourcePath);
    try {
      await src.rename(target);
    } on FileSystemException {
      await src.copy(target);
      await src.delete().catchError((_) => src);
    }
    return target;
  }

  Future<void> deleteDoc(String docId) async {
    final d = docDir(docId);
    if (d.existsSync()) await d.delete(recursive: true);
  }

  Future<void> deletePageFiles(String docId, String pageId) async {
    final original = File(originalPath(docId, pageId));
    if (original.existsSync()) await original.delete();
    await pruneCaches(docId, pageId);
    await pruneOcrImages(docId, pageId);
  }

  Future<void> deleteFile(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }

  /// Export temp + processed/thumb caches. They rebuild on demand.
  Future<void> clearCaches() async {
    await clearExportTemp();
    final docs = Directory(p.join(_root.path, 'docs'));
    if (!docs.existsSync()) return;
    await for (final doc in docs.list()) {
      if (doc is! Directory) continue;
      for (final sub in ['processed', 'thumb']) {
        final d = Directory(p.join(doc.path, sub));
        if (d.existsSync()) {
          await d.delete(recursive: true);
          await d.create();
        }
      }
    }
  }

  Future<void> clearExportTemp() async {
    for (final dir in [_exportTemp, _captureTemp]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }

  Future<int> usedBytes() async {
    var total = 0;
    if (!_root.existsSync()) return 0;
    await for (final e in _root.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
