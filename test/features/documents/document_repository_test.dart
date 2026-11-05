import 'dart:io';

import 'package:drift/native.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/data/repositories/document_repository_impl.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FileStore files;
  late DocumentRepositoryImpl repo;

  ScanPage draft(String id) {
    final path = files.newCapturePath(id);
    File(path).writeAsBytesSync([1, 2, 3]);
    return ScanPage(
      id: id,
      documentId: '',
      originalPath: path,
      edits: PageEdits(crop: Quad.full()),
      order: 0,
    );
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('flashdox_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    files = FileStore();
    await files.init();
    db = AppDatabase.test(NativeDatabase.memory());
    repo = DocumentRepositoryImpl(db, files);
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('create moves originals into the document folder and logs activity', () async {
    final r = await repo.create(mode: ScanMode.document, pages: [draft('a')]);
    final doc = r.getOrElse((f) => fail('$f'));
    expect(doc.pages.single.originalPath, files.originalPath(doc.id, 'a'));
    expect(File(doc.pages.single.originalPath).existsSync(), isTrue);
    expect(doc.lastActivity?.type, ActivityType.created);

    final all = await repo.watchAll().first;
    expect(all.single.id, doc.id);
    expect(all.single.title, startsWith('Flash Scan - '));
  });

  test('default names are "Flash Scan - DD Mon YYYY", then (2), (3)', () async {
    final titles = <String>[];
    for (var i = 0; i < 3; i++) {
      final d = (await repo.create(mode: ScanMode.document, pages: [draft('p$i')])).getOrElse((f) => fail('$f'));
      titles.add(d.title);
    }
    final base = DocumentRepositoryImpl.defaultTitleFor(DateTime.now());
    expect(base, matches(RegExp(r'^Flash Scan - \d{2} [A-Z][a-z]{2} \d{4}$')));
    expect(titles, [base, '$base (2)', '$base (3)']);
  });

  test('rename, addPages, reorder, deletePage, delete', () async {
    final doc = (await repo.create(mode: ScanMode.document, pages: [draft('a'), draft('b')]))
        .getOrElse((f) => fail('$f'));

    expect((await repo.rename(doc.id, 'Receipts')).isRight(), isTrue);
    expect((await repo.addPages(doc.id, [draft('c')])).isRight(), isTrue);
    var cur = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
    expect(cur.title, 'Receipts');
    expect(cur.sortedPages.map((p) => p.id), ['a', 'b', 'c']);
    expect(cur.lastActivity?.type, ActivityType.edited);

    expect((await repo.reorder(doc.id, ['c', 'a', 'b'])).isRight(), isTrue);
    cur = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
    expect(cur.sortedPages.map((p) => p.id), ['c', 'a', 'b']);

    expect((await repo.deletePage('a')).isRight(), isTrue);
    cur = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
    expect(cur.pages.map((p) => p.id), isNot(contains('a')));
    expect(File(files.originalPath(doc.id, 'a')).existsSync(), isFalse);

    expect((await repo.delete(doc.id)).isRight(), isTrue);
    expect((await repo.get(doc.id)).isLeft(), isTrue);
    expect(files.docDir(doc.id).existsSync(), isFalse);
  });

  test('updatePage persists edits and clears caches; watch emits', () async {
    final doc = (await repo.create(mode: ScanMode.document, pages: [draft('a')]))
        .getOrElse((f) => fail('$f'));
    final page = doc.pages.single.copyWith(processedPath: '/x', ocrText: 'hi');
    await repo.updatePage(page);
    var cur = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
    expect(cur.pages.single.ocrText, 'hi');

    await repo.updatePage(cur.pages.single.withEdits(const PageEdits(filter: FilterType.bwPrint)));
    cur = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
    expect(cur.pages.single.ocrText, isNull);
    expect(cur.pages.single.edits.filter, FilterType.bwPrint);

    final stream = repo.watch(doc.id);
    expect((await stream.first)?.id, doc.id);
  });

  test('search filters by title and ordering is newest first', () async {
    final a = (await repo.create(mode: ScanMode.document, pages: [draft('a')], title: 'Alpha')).getOrElse((f) => fail('$f'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = (await repo.create(mode: ScanMode.document, pages: [draft('b')], title: 'Beta')).getOrElse((f) => fail('$f'));
    final all = await repo.watchAll().first;
    expect(all.map((d) => d.id), [b.id, a.id]);
    final filtered = await repo.watchAll(search: 'alp').first;
    expect(filtered.map((d) => d.id), [a.id]);
  });
}
