import 'dart:io';

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
    for (final path in [
      originalPath(docId, pageId),
      processedPath(docId, pageId),
      thumbPath(docId, pageId),
    ]) {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    }
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
