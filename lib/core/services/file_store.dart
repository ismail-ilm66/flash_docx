import 'dart:convert';
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
/// <app documents>/flashdox/docs/<docId>/export/<pageId>_<size>_<key>.jpg  # export page renders (cache)
/// <temp>/flashdox_export/                                        # cleared on launch
/// <temp>/flashdox_capture/                                       # camera shots awaiting a document,
///                                                                # editor previews, cleaned bases
/// ```
@lazySingleton
class FileStore {
  late final Directory _root;
  late final Directory _exportTemp;
  late final Directory _captureTemp;

  /// Round 6 moved export page renders into the document folders; this temp
  /// folder (older builds) is removed on launch.
  late final Directory _legacyExportCache;

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
    _legacyExportCache = Directory(p.join(tmp.path, 'flashdox_export_cache'));
    await Future.wait([
      Directory(p.join(_root.path, 'docs')).create(recursive: true),
      _exportTemp.create(recursive: true),
      _captureTemp.create(recursive: true),
    ]);
  }

  Directory docDir(String docId) =>
      Directory(p.join(_root.path, 'docs', docId));

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
  Future<void> pruneOcrImages(
    String docId,
    String pageId, {
    String? keep,
  }) async {
    final dir = Directory(p.join(docDir(docId).path, 'processed'));
    if (!dir.existsSync()) return;
    await for (final f in dir.list()) {
      if (f is File &&
          p.basename(f.path).startsWith('${pageId}_ocr_') &&
          f.path != keep) {
        await f.delete();
      }
    }
  }

  /// Editor base preview (upright, uncropped, preview size) for a page. Keyed
  /// by the original's path so a retake or a moved original gets a new one.
  String basePreviewPath(String pageId, String originalPath) =>
      p.join(_captureTemp.path, 'base_${pageId}_${_stamp(originalPath)}.jpg');

  /// Cropped + rotated page at preview size, reused while switching filters.
  String workPath(
    String pageId,
    String originalPath,
    PageEdits edits,
  ) => p.join(
    _captureTemp.path,
    'work_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect)}.jpg',
  );

  /// The Auto filter of the page's cleaned preview (round 6; before that, of
  /// the [workPath] page), lossless (PNG): Auto, Colour Boost and Grayscale
  /// previews all start from it.
  String autoBasePath(
    String pageId,
    String originalPath,
    PageEdits edits,
  ) => p.join(
    _captureTemp.path,
    'auto_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect)}.png',
  );

  /// Round 6, P0-2: the page cropped, turned and cleaned once at
  /// [longEdge] (export size), lossless. [card]: the ID colour strength.
  String cleanBasePath(
    String pageId,
    String originalPath,
    PageEdits edits, {
    required int longEdge,
    required bool card,
  }) => p.join(
    _captureTemp.path,
    'clean_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect, longEdge, card)}.png',
  );

  /// The cleaned base at preview size, written with it: Enhance's filters
  /// start from this.
  String cleanPreviewPath(
    String pageId,
    String originalPath,
    PageEdits edits, {
    required bool card,
  }) => p.join(
    _captureTemp.path,
    'cleanprev_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect, card)}.png',
  );

  /// Enhance's first image for one filter, before the cleaned base exists.
  String instantLookPath(
    String pageId,
    String originalPath,
    PageEdits edits,
  ) => p.join(
    _captureTemp.path,
    'instant_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect, edits.filter)}.jpg',
  );

  /// Enhance preview for one filter (sliders are applied live, not baked).
  String lookPath(
    String pageId,
    String originalPath,
    PageEdits edits,
  ) => p.join(
    _captureTemp.path,
    'look_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect, edits.filter)}.jpg',
  );

  /// The fast crop-only placeholder (P0-4) for one crop / rotation.
  String quickPath(
    String pageId,
    String originalPath,
    PageEdits edits,
  ) => p.join(
    _captureTemp.path,
    'quick_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect)}.jpg',
  );

  /// One 160 px filter thumbnail for Enhance's filter strip.
  String stripPath(
    String pageId,
    String originalPath,
    PageEdits edits,
    FilterType filter,
  ) => p.join(
    _captureTemp.path,
    'strip_${pageId}_${Object.hash(_stamp(originalPath), edits.crop, edits.normalizedTurns, edits.outputAspect)}_${filter.name}.jpg',
  );

  /// Sign a document (feature 4): the page without its overlays, which the
  /// screen draws as movable boxes instead.
  String signBasePath(String pageId, String originalPath, PageEdits edits) => p.join(
    _captureTemp.path,
    'sign_${pageId}_${Object.hash(_stamp(originalPath), edits.copyWith(overlays: const []))}.jpg',
  );

  /// One page rendered for export at one size and JPEG quality (P0-4).
  /// Shared by every export of the same look, so a page-size or format change
  /// doesn't re-render. Kept with the document (round 6: made right after
  /// Done, so the first Share only builds the PDF, also after a relaunch);
  /// the name must be the same on every run, so no `Object.hash` here.
  String exportPagePath(
    String docId,
    String pageId,
    String originalPath,
    PageEdits edits, {
    required String sizeKey,
    required int jpegQuality,
  }) {
    final f = File(originalPath);
    final st = f.existsSync() ? f.statSync() : null;
    final version = '${st?.size}|${st?.modified.microsecondsSinceEpoch}';
    final key = stableKey('$version|${jsonEncode(edits.toJson())}|$sizeKey|$jpegQuality');
    return p.join(docDir(docId).path, 'export', '${pageId}_${sizeKey}_$key.jpg');
  }

  /// Removes a page's other export renders of [sizeKey] (an older look).
  Future<void> pruneExportPages(String docId, String pageId, String sizeKey, {required String keep}) async {
    final dir = Directory(p.join(docDir(docId).path, 'export'));
    if (!dir.existsSync()) return;
    await for (final f in dir.list()) {
      if (f is! File || f.path == keep) continue;
      if (p.basename(f.path).startsWith('${pageId}_${sizeKey}_')) {
        await f.delete().catchError((_) => f);
      }
    }
  }

  /// FNV-1a (64-bit) of [s] as 16 hex digits: a file-name key that, unlike
  /// `Object.hash`, is the same on every launch.
  static String stableKey(String s) {
    var h = (0xcbf29ce4 << 32) | 0x84222325; // the FNV offset basis
    for (final b in utf8.encode(s)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex(h >>> 32)}${hex(h & 0xffffffff)}';
  }

  /// Identifies one version of an original by its size and modification
  /// time, not its path: Done moves the file into the document folder
  /// (`adoptOriginal`, a rename keeps both), and the previews made while
  /// editing must still match it there. Names also carry the page id, and a
  /// retake over the same file changes the stamp.
  int _stamp(String originalPath) {
    final f = File(originalPath);
    if (!f.existsSync()) return 0;
    final st = f.statSync();
    return Object.hash(st.size, st.modified.microsecondsSinceEpoch);
  }

  /// True when [path] already lives inside the document's folder.
  bool isInDoc(String docId, String path) =>
      p.isWithin(docDir(docId).path, path);

  /// New, never-before-used file names for a page's viewer caches. A fresh
  /// name means Flutter's image cache can never show a stale render, so
  /// nothing has to be evicted. Old versions are removed by [pruneCaches].
  ({String processed, String thumb}) newCachePaths(
    String docId,
    String pageId,
  ) {
    final v = DateTime.now().microsecondsSinceEpoch;
    return (
      processed: p.join(docDir(docId).path, 'processed', '${pageId}_v$v.jpg'),
      thumb: p.join(docDir(docId).path, 'thumb', '${pageId}_v$v.jpg'),
    );
  }

  /// Deletes a page's cache files except [keep] (legacy fixed names too).
  Future<void> pruneCaches(
    String docId,
    String pageId, {
    Set<String> keep = const {},
  }) async {
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

  /// After the share sheet or save closes (round 6, P0-3): removes the
  /// folders holding [paths] inside the export temp folder (a staging or
  /// `out_` folder). Files elsewhere, such as cached page renders, are left
  /// alone.
  Future<void> discardExportFiles(Iterable<String> paths) async {
    final dirs = {
      for (final f in paths)
        if (p.isWithin(_exportTemp.path, f)) p.dirname(f),
    };
    for (final d in dirs) {
      if (!p.isWithin(_exportTemp.path, d)) continue; // never the root
      try {
        await Directory(d).delete(recursive: true);
      } on FileSystemException {
        // Already gone, or still open somewhere: launch clears it anyway.
      }
    }
  }

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
    final exports = Directory(p.join(docDir(docId).path, 'export'));
    if (exports.existsSync()) {
      await for (final f in exports.list()) {
        if (f is File && p.basename(f.path).startsWith('${pageId}_')) {
          await f.delete().catchError((_) => f);
        }
      }
    }
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
      for (final sub in ['processed', 'thumb', 'export']) {
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
    if (_legacyExportCache.existsSync()) {
      await _legacyExportCache.delete(recursive: true);
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
