import 'dart:io';

import 'package:drift/native.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/data/draft_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

/// Round 7, P0-3: a scan survives the app being closed, killed or crashing.
void main() {
  late Directory tmp;
  late FileStore files;
  late Database raw;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('drafts');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    raw = sqlite3.openInMemory();
  });

  tearDown(() async {
    raw.close();
    await tmp.delete(recursive: true);
  });

  /// One app run: its own database connection over the same data.
  AppDatabase open() => AppDatabase.test(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));

  ScanPage page(String id, {double inset = 0.1, bool detected = true}) {
    final path = files.newOriginalPath(id);
    File(path).writeAsBytesSync([1]);
    return ScanPage(
      id: id,
      documentId: '',
      originalPath: path,
      edits: PageEdits(crop: Quad.full(inset: inset), filter: FilterType.grayscale),
      order: 0,
      edgesDetected: detected,
    );
  }

  test('pages saved in one run come back, in order, in the next', () async {
    final db = open();
    final a = page('a');
    final b = page('b', inset: 0.2, detected: false);
    await DraftService(db, files).save(ScanMode.document, [a, b]);
    await db.close();

    final db2 = open();
    final next = DraftService(db2, files);
    await next.init();
    final d = next.pending.value!;
    expect(d.mode, ScanMode.document);
    expect([for (final x in d.pages) x.id], ['a', 'b']);
    expect(d.pages[1].edits, b.edits, reason: 'crop corners and filter');
    expect(d.pages[1].edgesDetected, isFalse);
    expect(d.pages[1].order, 1);
    await db2.close();
  });

  test('original photos live outside temp, which launch clears', () {
    expect(p.isWithin(files.captureTemp.path, files.newOriginalPath('x')), isFalse);
    expect(p.isWithin(files.root.path, files.newOriginalPath('x')), isTrue);
  });

  test('launch deletes draft photos nothing uses, keeps the rest', () async {
    final db = open();
    final kept = page('kept');
    final orphan = page('orphan');
    final saved = page('saved'); // in a document, not adopted (paranoia)
    await db.into(db.documents).insert(
          DocumentsCompanion.insert(id: 'd', title: 'D', mode: ScanMode.document, createdAt: DateTime(2026), updatedAt: DateTime(2026)),
        );
    await db.into(db.pages).insert(AppDatabase.pageToCompanion(saved.copyWith(documentId: 'd')));
    final drafts = DraftService(db, files);
    await drafts.save(ScanMode.document, [kept]);
    await drafts.init();
    expect(File(kept.originalPath).existsSync(), isTrue);
    expect(File(saved.originalPath).existsSync(), isTrue);
    expect(File(orphan.originalPath).existsSync(), isFalse);
    await db.close();
  });

  test('Discard deletes the rows and the photos', () async {
    final db = open();
    final a = page('a');
    final drafts = DraftService(db, files);
    await drafts.save(ScanMode.document, [a]);
    await drafts.discard();
    expect(File(a.originalPath).existsSync(), isFalse);
    await drafts.init();
    expect(drafts.pending.value, isNull);
    await db.close();
  });

  test('a saved scan clears the draft but keeps the photos for its document', () async {
    final db = open();
    final a = page('a');
    final drafts = DraftService(db, files);
    await drafts.save(ScanMode.document, [a]);
    await drafts.finished();
    expect(await db.select(db.draftPages).get(), isEmpty);
    expect(File(a.originalPath).existsSync(), isTrue);
    await db.close();
  });

  test('Continue hands the draft over and hides the Home card', () async {
    final db = open();
    final drafts = DraftService(db, files);
    await drafts.save(ScanMode.idCard, [page('a')]);
    await drafts.init();
    final d = drafts.takePending();
    expect(d!.mode, ScanMode.idCard);
    expect(drafts.pending.value, isNull);
    await db.close();
  });

  test('a new scan replaces a draft nobody continued, and deletes its photos', () async {
    final db = open();
    final old = page('old');
    final drafts = DraftService(db, files);
    await drafts.save(ScanMode.document, [old]);
    await drafts.init();
    expect(drafts.pending.value, isNotNull);
    final fresh = page('fresh');
    await drafts.save(ScanMode.document, [fresh]);
    expect(File(old.originalPath).existsSync(), isFalse);
    expect(File(fresh.originalPath).existsSync(), isTrue);
    expect(drafts.pending.value, isNull);
    await db.close();
  });

  test('a page whose photo is gone is left out', () async {
    final db = open();
    final a = page('a');
    final b = page('b');
    final drafts = DraftService(db, files);
    await drafts.save(ScanMode.document, [a, b]);
    File(a.originalPath).deleteSync();
    await drafts.init();
    expect([for (final x in drafts.pending.value!.pages) x.id], ['b']);
    await db.close();
  });
}
