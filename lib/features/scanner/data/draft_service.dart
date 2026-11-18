import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// A scan that was never saved or discarded (round 7, P0-3).
class ScanDraft {
  const ScanDraft(this.mode, this.pages);
  final ScanMode mode;
  final List<ScanPage> pages;
}

/// Keeps the scan being made on disk, page by page: the originals in
/// [FileStore.draftDir] and one `draft_pages` row per page (crop, filter,
/// order). If the app is closed, killed or crashes, Home offers to
/// continue it.
@lazySingleton
class DraftService {
  DraftService(this._db, this._files);

  final AppDatabase _db;
  final FileStore _files;

  /// The draft left by an earlier run, for the Home card; null once it is
  /// continued, discarded or replaced by a new scan.
  final ValueNotifier<ScanDraft?> pending = ValueNotifier(null);

  /// Writes run one after another, in the order they were asked for.
  Future<void> _chain = Future.value();

  Future<void> _run(Future<void> Function() job) {
    final next = _chain.then((_) => job()).catchError((Object e) {
      debugPrint('[draft] $e');
    });
    _chain = next;
    return next;
  }

  /// At launch: loads the earlier run's draft into [pending], and deletes
  /// draft-folder files that no draft row or saved page uses.
  Future<void> init() => _run(() async {
        final draft = await _load();
        pending.value = draft;
        final used = {
          ...?draft?.pages.map((pg) => pg.originalPath),
          for (final r in await _db.select(_db.pages).get()) r.originalPath,
        };
        final dir = _files.draftDir;
        if (!dir.existsSync()) return;
        await for (final f in dir.list()) {
          if (f is File && !used.contains(f.path)) {
            await f.delete().catchError((_) => f);
          }
        }
      });

  /// Replaces the draft with [pages] (empty clears it). The scan in this
  /// run takes over: an earlier draft nobody continued is deleted.
  Future<void> save(ScanMode mode, List<ScanPage> pages) {
    final stale = pending.value;
    pending.value = null;
    return _run(() async {
      if (stale != null) await _deleteFiles(stale.pages, keep: pages);
      final now = DateTime.now();
      await _db.transaction(() async {
        await _db.delete(_db.draftPages).go();
        for (final (i, pg) in pages.indexed) {
          await _db.into(_db.draftPages).insert(
                DraftPagesCompanion.insert(
                  id: pg.id,
                  mode: mode,
                  originalPath: pg.originalPath,
                  editsJson: jsonEncode(pg.edits.toJson()),
                  pageOrder: i,
                  side: Value(pg.side),
                  edgesDetected: Value(pg.edgesDetected),
                  savedAt: now,
                ),
              );
        }
      });
    });
  }

  /// The scan was saved: its files now belong to the document.
  Future<void> finished() {
    pending.value = null;
    return _run(() => _db.delete(_db.draftPages).go());
  }

  /// Discard: the rows and the page originals go.
  Future<void> discard() {
    final stale = pending.value;
    pending.value = null;
    return _run(() async {
      final draft = await _load();
      await _db.delete(_db.draftPages).go();
      await _deleteFiles([...?draft?.pages, ...?stale?.pages]);
    });
  }

  /// "Continue": the draft is handed to the editor, which keeps saving it.
  ScanDraft? takePending() {
    final d = pending.value;
    pending.value = null;
    return d;
  }

  Future<ScanDraft?> _load() async {
    final rows = await (_db.select(_db.draftPages)..orderBy([(r) => OrderingTerm(expression: r.pageOrder)])).get();
    final pages = <ScanPage>[
      for (final r in rows)
        if (File(r.originalPath).existsSync())
          ScanPage(
            id: r.id,
            documentId: '',
            originalPath: r.originalPath,
            edits: PageEdits.fromJson(jsonDecode(r.editsJson) as Map<String, dynamic>),
            order: r.pageOrder,
            side: r.side,
            edgesDetected: r.edgesDetected,
          ),
    ];
    if (pages.isEmpty) return null;
    return ScanDraft(rows.first.mode, [for (final (i, pg) in pages.indexed) pg.copyWith(order: i)]);
  }

  /// Deletes the originals of [pages] that are in the draft folder, except
  /// those [keep] still uses.
  Future<void> _deleteFiles(List<ScanPage> pages, {List<ScanPage> keep = const []}) async {
    final kept = {for (final pg in keep) pg.originalPath};
    for (final pg in pages) {
      final path = pg.originalPath;
      if (kept.contains(path) || !p.isWithin(_files.draftDir.path, path)) continue;
      await File(path).delete().catchError((_) => File(path));
    }
  }
}
