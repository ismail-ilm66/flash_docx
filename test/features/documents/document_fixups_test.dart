import 'dart:io';

import 'package:drift/native.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/data/repositories/document_repository_impl.dart';
import 'package:flash_dox/features/documents/data/services/document_fixups.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

/// Round 11b, G2 / H1: older documents fixed once at start-up.
void main() {
  late Directory tmp;
  late FileStore files;
  late DocumentRepositoryImpl repo;
  late AppDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fixups');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    db = AppDatabase.test(NativeDatabase.memory());
    repo = DocumentRepositoryImpl(db, files);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  ScanPage draft(String id) {
    final path = files.newCapturePath(id);
    File(path).writeAsBytesSync([1]);
    return ScanPage(id: id, documentId: '', originalPath: path, edits: const PageEdits(), order: 0);
  }

  test('a 4-side ID card becomes two; a passport photo document keeps one page', () async {
    final card = (await repo.create(mode: ScanMode.idCard, pages: [for (final id in ['f1', 'b1', 'f2', 'b2']) draft(id)], title: 'CNIC')).getOrElse((f) => fail('$f'));
    final photo = (await repo.create(mode: ScanMode.photo, pages: [draft('ph1'), draft('ph2')], title: 'Passport photo')).getOrElse((f) => fail('$f'));
    // The second photo page lost its file (the blank page 2).
    File(photo.sortedPages.last.originalPath).deleteSync();
    final fixups = DocumentFixups(repo, PrefsService(await SharedPreferences.getInstance()));
    await fixups.run();

    final all = await repo.watchAll().first;
    final cards = all.where((d) => d.mode == ScanMode.idCard).toList();
    expect(cards.map((d) => d.pages.length), [2, 2]);
    expect(cards.map((d) => d.title), containsAll(['CNIC', 'ID card – front & back (2)']));
    expect((await repo.get(card.id)).getOrElse((f) => fail('$f')).sortedPages.map((p) => p.id), ['f1', 'b1']);
    final photos = all.where((d) => d.mode == ScanMode.photo).toList();
    expect(photos.single.pages.single.id, 'ph1');

    // Only once.
    await fixups.run();
    expect((await repo.watchAll().first).length, all.length);
  });
}
