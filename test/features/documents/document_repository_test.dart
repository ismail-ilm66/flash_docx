import 'dart:io';

import 'package:drift/native.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/data/repositories/document_repository_impl.dart';
import 'package:flash_dox/features/documents/data/services/smart_namer.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/smart_rules.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/ocr/domain/recognize_page_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
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
  setUpAll(() => registerFallbackValue(const ScanPage(id: '', documentId: '', originalPath: '', edits: PageEdits(), order: 0)));

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
    // Round 11, P1-1: recognised text counts too.
    await repo.updatePage(b.pages.single.copyWith(ocrText: 'Electricity bill October'));
    expect((await repo.watchAll(search: 'electricity').first).map((d) => d.id), [b.id]);
  });

  test('round 11, P0-13: pages move to another document or a new one', () async {
    final src = (await repo.create(mode: ScanMode.document, pages: [draft('m1'), draft('m2'), draft('m3')], title: 'Src')).getOrElse((f) => fail('$f'));
    final dst = (await repo.create(mode: ScanMode.document, pages: [draft('d1')], title: 'Dst')).getOrElse((f) => fail('$f'));
    expect((await repo.movePages(['m3', 'm1'], toDocumentId: dst.id)).getOrElse((f) => fail('$f')), dst.id);
    final to = (await repo.get(dst.id)).getOrElse((f) => fail('$f'));
    expect(to.sortedPages.map((p) => p.id), ['d1', 'm3', 'm1']);
    expect(File(files.originalPath(dst.id, 'm3')).existsSync(), isTrue);
    expect(File(files.originalPath(src.id, 'm3')).existsSync(), isFalse);
    final from = (await repo.get(src.id)).getOrElse((f) => fail('$f'));
    expect(from.pages.map((p) => p.id), ['m2']);

    // The last page to a new document: the old one goes.
    final newId = (await repo.movePages(['m2'])).getOrElse((f) => fail('$f'));
    expect((await repo.get(src.id)).isLeft(), isTrue);
    final fresh = (await repo.get(newId)).getOrElse((f) => fail('$f'));
    expect(fresh.pages.single.id, 'm2');
    expect(fresh.mode, ScanMode.document);
  });

  group('feature 3: folders, suggestions, sizes', () {
    test('cards go to IDs, documents to Other', () async {
      final card = (await repo.create(mode: ScanMode.idCard, pages: [draft('f'), draft('b')])).getOrElse((f) => fail('$f'));
      final doc = (await repo.create(mode: ScanMode.document, pages: [draft('d')])).getOrElse((f) => fail('$f'));
      expect(card.folder, DocFolder.ids);
      final all = await repo.watchAll().first;
      expect({for (final d in all) d.id: d.folder}, {card.id: DocFolder.ids, doc.id: DocFolder.other});
    });

    test('setFolder moves; setSuggestion stores without reordering Home', () async {
      final doc = (await repo.create(mode: ScanMode.document, pages: [draft('a')])).getOrElse((f) => fail('$f'));
      final before = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
      const s = NameSuggestion(title: 'Receipt – 02 Nov 2026', folder: DocFolder.receipts, kind: 'a receipt');
      await repo.setSuggestion(doc.id, s);
      await repo.setFolder(doc.id, DocFolder.bills);
      final after = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
      expect(after.suggestion, s);
      expect(after.folder, DocFolder.bills);
      expect(after.updatedAt, before.updatedAt);
    });

    test('size is the sum of the page files', () async {
      final doc = (await repo.create(mode: ScanMode.document, pages: [draft('a'), draft('b')])).getOrElse((f) => fail('$f'));
      final cur = (await repo.get(doc.id)).getOrElse((f) => fail('$f'));
      expect(cur.sizeBytes, 6, reason: 'two 3-byte originals');
    });

    test('Apply renames, files it and hides the banner; ✕ only hides it', () async {
      final actions = NameSuggestionActions(repo);
      const s = NameSuggestion(title: 'Electricity bill – Oct 2026', folder: DocFolder.bills, kind: 'an electricity bill');
      final a = (await repo.create(mode: ScanMode.document, pages: [draft('a')])).getOrElse((f) => fail('$f'));
      await repo.setSuggestion(a.id, s);
      await actions.apply((await repo.get(a.id)).getOrElse((f) => fail('$f')));
      final applied = (await repo.get(a.id)).getOrElse((f) => fail('$f'));
      expect(applied.title, s.title);
      expect(applied.folder, DocFolder.bills);
      expect(applied.suggestion?.dismissed, isTrue);

      final b = (await repo.create(mode: ScanMode.document, pages: [draft('b')])).getOrElse((f) => fail('$f'));
      await repo.setSuggestion(b.id, s);
      await actions.dismiss((await repo.get(b.id)).getOrElse((f) => fail('$f')));
      final dismissed = (await repo.get(b.id)).getOrElse((f) => fail('$f'));
      expect(dismissed.title, b.title);
      expect(dismissed.folder, DocFolder.other);
      expect(dismissed.suggestion?.dismissed, isTrue);
    });

    test('SmartNamer stores a suggestion once, from page-1 text', () async {
      final ocr = _Ocr();
      final namer = SmartNamer(repo, ocr)..useRules(SmartRules.fromJson(File('assets/smart_rules.json').readAsStringSync()));
      when(() => ocr(any(), force: any(named: 'force')))
          .thenAnswer((_) async => const Right('LESCO  BILL MONTH OCT 26  UNITS CONSUMED 312'));
      final doc = (await repo.create(mode: ScanMode.document, pages: [draft('a')])).getOrElse((f) => fail('$f'));
      await namer.suggestFor(doc.id);
      final s = (await repo.get(doc.id)).getOrElse((f) => fail('$f')).suggestion!;
      expect(s.title, 'Electricity bill – Oct 2026');
      expect(s.folder, DocFolder.bills);
      expect((await repo.get(doc.id)).getOrElse((f) => fail('$f')).title, doc.title, reason: 'never applied silently');

      await namer.suggestFor(doc.id);
      verify(() => ocr(any(), force: any(named: 'force'))).called(1);
    });

    test('SmartNamer stores nothing when nothing matches or OCR fails', () async {
      final ocr = _Ocr();
      final namer = SmartNamer(repo, ocr)..useRules(SmartRules.fromJson(File('assets/smart_rules.json').readAsStringSync()));
      when(() => ocr(any(), force: any(named: 'force'))).thenAnswer((_) async => const Left(OcrFailure()));
      final doc = (await repo.create(mode: ScanMode.document, pages: [draft('a')])).getOrElse((f) => fail('$f'));
      await namer.suggestFor(doc.id);
      expect((await repo.get(doc.id)).getOrElse((f) => fail('$f')).suggestion, isNull);
    });
  });
}

class _Ocr extends Mock implements RecognizePageText {}
