import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flash_dox/core/error/app_exception.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: DocumentRepository)
class DocumentRepositoryImpl implements DocumentRepository {
  DocumentRepositoryImpl(this._db, this._files);

  final AppDatabase _db;
  final FileStore _files;

  Failure _dbFail(Object e, StackTrace _) => DatabaseFailure(e.toString());

  // ---------- queries ----------

  @override
  Stream<List<ScanDocument>> watchAll({String? search}) {
    final q = _db.select(_db.documents)
      ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]);
    if (search != null && search.trim().isNotEmpty) {
      q.where((d) => d.title.like('%${search.trim()}%'));
    }
    final docs$ = q.watch();
    final pages$ = _db.select(_db.pages).watch();
    final acts$ = _db.select(_db.activities).watch();

    // Combine the three streams; recompute on any change.
    late StreamController<List<ScanDocument>> ctrl;
    List<DocumentRow>? docs;
    List<PageRow>? pages;
    List<ActivityRow>? acts;
    final subs = <StreamSubscription<dynamic>>[];

    void emit() {
      if (docs == null || pages == null || acts == null) return;
      ctrl.add(_assemble(docs!, pages!, acts!));
    }

    ctrl = StreamController<List<ScanDocument>>(
      onListen: () {
        subs
          ..add(docs$.listen((d) { docs = d; emit(); }, onError: ctrl.addError))
          ..add(pages$.listen((p) { pages = p; emit(); }, onError: ctrl.addError))
          ..add(acts$.listen((a) { acts = a; emit(); }, onError: ctrl.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return ctrl.stream;
  }

  @override
  Stream<ScanDocument?> watch(String id) {
    return watchAll().map((all) => all.where((d) => d.id == id).firstOrNull);
  }

  @override
  Future<Either<Failure, ScanDocument>> get(String id) async {
    try {
      final doc = await (_db.select(_db.documents)..where((d) => d.id.equals(id)))
          .getSingleOrNull();
      if (doc == null) return const Left(NotFoundFailure());
      final pages = await (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(id)))
          .get();
      final acts = await (_db.select(_db.activities)
            ..where((a) => a.documentId.equals(id)))
          .get();
      return Right(_assemble([doc], pages, acts).first);
    } catch (e) {
      return Left(DatabaseFailure(e.toString()));
    }
  }

  List<ScanDocument> _assemble(
    List<DocumentRow> docs,
    List<PageRow> pages,
    List<ActivityRow> acts,
  ) {
    final pagesBy = <String, List<ScanPage>>{};
    for (final p in pages) {
      pagesBy.putIfAbsent(p.documentId, () => []).add(AppDatabase.pageFromRow(p));
    }
    final lastBy = <String, ActivityRow>{};
    for (final a in acts) {
      final cur = lastBy[a.documentId];
      if (cur == null || a.at.isAfter(cur.at)) lastBy[a.documentId] = a;
    }
    return [
      for (final d in docs)
        ScanDocument(
          id: d.id,
          title: d.title,
          mode: d.mode,
          pages: (pagesBy[d.id] ?? const [])
            ..sort((a, b) => a.order.compareTo(b.order)),
          createdAt: d.createdAt,
          updatedAt: d.updatedAt,
          lastActivity: lastBy[d.id] == null
              ? null
              : AppDatabase.activityFromRow(lastBy[d.id]!),
        ),
    ];
  }

  // ---------- mutations ----------

  @override
  Future<Either<Failure, ScanDocument>> create({
    required ScanMode mode,
    required List<ScanPage> pages,
    String? title,
  }) async {
    final docId = newId();
    final now = DateTime.now();
    final docTitle = title ?? _defaultTitle(mode, now);
    try {
      // Move originals into the document folder first so the DB never points
      // at files that don't exist.
      final adopted = <ScanPage>[];
      for (final (i, p) in pages.indexed) {
        final path = await _files.adoptOriginal(
          sourcePath: p.originalPath,
          docId: docId,
          pageId: p.id,
        );
        adopted.add(p.copyWith(documentId: docId, originalPath: path, order: i));
      }
      await _db.transaction(() async {
        await _db.into(_db.documents).insert(
              DocumentsCompanion.insert(
                id: docId,
                title: docTitle,
                mode: mode,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _db.batch((b) {
          b.insertAll(_db.pages, adopted.map(AppDatabase.pageToCompanion));
        });
        await _insertActivity(docId, ActivityType.created, now);
      });
      return Right(
        ScanDocument(
          id: docId,
          title: docTitle,
          mode: mode,
          pages: adopted,
          createdAt: now,
          updatedAt: now,
          lastActivity: Activity(
            id: '',
            documentId: docId,
            type: ActivityType.created,
            at: now,
          ),
        ),
      );
    } catch (e) {
      await _files.deleteDoc(docId);
      return Left(
        e is DriftWrappedException || e is InvalidDataException
            ? DatabaseFailure(e.toString())
            : StorageFailure(e.toString()),
      );
    }
  }

  String _defaultTitle(ScanMode mode, DateTime at) {
    final prefix = switch (mode) {
      ScanMode.single => 'Scan',
      ScanMode.batch => 'Scan',
      ScanMode.idCard => 'ID card',
      ScanMode.passport => 'Passport',
    };
    String two(int v) => v.toString().padLeft(2, '0');
    return '$prefix ${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}${two(at.minute)}';
  }

  @override
  Future<Either<Failure, Unit>> rename(String id, String title) => guard(
        () async {
          await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
            DocumentsCompanion(
              title: Value(title),
              updatedAt: Value(DateTime.now()),
            ),
          );
          return unit;
        },
        onError: _dbFail,
      );

  @override
  Future<Either<Failure, Unit>> addPages(String id, List<ScanPage> pages) async {
    try {
      final existing = await (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(id)))
          .get();
      var order = existing.isEmpty
          ? 0
          : existing.map((p) => p.pageOrder).reduce((a, b) => a > b ? a : b) + 1;
      final adopted = <ScanPage>[];
      for (final p in pages) {
        final path = await _files.adoptOriginal(
          sourcePath: p.originalPath,
          docId: id,
          pageId: p.id,
        );
        adopted.add(p.copyWith(documentId: id, originalPath: path, order: order++));
      }
      await _db.transaction(() async {
        await _db.batch((b) {
          b.insertAll(_db.pages, adopted.map(AppDatabase.pageToCompanion));
        });
        await _touch(id);
        await _insertActivity(id, ActivityType.edited, DateTime.now());
      });
      return const Right(unit);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> reorder(String id, List<String> pageIds) => guard(
        () async {
          await _db.transaction(() async {
            for (final (i, pid) in pageIds.indexed) {
              await (_db.update(_db.pages)..where((p) => p.id.equals(pid)))
                  .write(PagesCompanion(pageOrder: Value(i)));
            }
            await _touch(id);
          });
          return unit;
        },
        onError: _dbFail,
      );

  @override
  Future<Either<Failure, Unit>> updatePage(ScanPage page) =>
      updatePages([page]);

  @override
  Future<Either<Failure, Unit>> updatePages(List<ScanPage> pages) => guard(
        () async {
          if (pages.isEmpty) return unit;
          await _db.transaction(() async {
            for (final p in pages) {
              await _db
                  .into(_db.pages)
                  .insertOnConflictUpdate(AppDatabase.pageToCompanion(p));
            }
            await _touch(pages.first.documentId);
          });
          return unit;
        },
        onError: _dbFail,
      );

  @override
  Future<Either<Failure, Unit>> deletePage(String pageId) async {
    try {
      final row = await (_db.select(_db.pages)..where((p) => p.id.equals(pageId)))
          .getSingleOrNull();
      if (row == null) return const Left(NotFoundFailure());
      await _db.transaction(() async {
        await (_db.delete(_db.pages)..where((p) => p.id.equals(pageId))).go();
        await _touch(row.documentId);
      });
      await _files.deletePageFiles(row.documentId, pageId);
      return const Right(unit);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> delete(String id) async {
    try {
      await (_db.delete(_db.documents)..where((d) => d.id.equals(id))).go();
      await _files.deleteDoc(id);
      return const Right(unit);
    } catch (e) {
      return Left(StorageFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> logActivity(String id, ActivityType type) =>
      guard(
        () async {
          final now = DateTime.now();
          await _db.transaction(() async {
            await _insertActivity(id, type, now);
            await _touch(id, now);
          });
          return unit;
        },
        onError: _dbFail,
      );

  @override
  Future<Either<Failure, int>> storageUsedBytes() => guard(
        _files.usedBytes,
        onError: (e, _) => StorageFailure(e.toString()),
      );

  Future<void> _insertActivity(String docId, ActivityType type, DateTime at) =>
      _db.into(_db.activities).insert(
            ActivitiesCompanion.insert(
              id: newId(),
              documentId: docId,
              type: type,
              at: at,
            ),
          );

  Future<void> _touch(String docId, [DateTime? at]) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(docId)))
          .write(DocumentsCompanion(updatedAt: Value(at ?? DateTime.now())));
}
