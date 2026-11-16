import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

void main() {
  late Directory tmp;
  late FileStore files;
  late String original;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('file_store');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    original = files.newCapturePath('orig');
    File(original).writeAsBytesSync([1]);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('stableKey is 64-bit FNV-1a (the same on every launch)', () {
    expect(FileStore.stableKey(''), 'cbf29ce484222325');
    expect(FileStore.stableKey('a'), 'af63dc4c8601ec8c');
    expect(FileStore.stableKey('foobar'), '85944171f73967e8');
  });

  test('export page renders: same look, same name; another crop, another', () {
    String path(PageEdits e, {String size = 'standard'}) =>
        files.exportPagePath('p1', original, e, sizeKey: size, jpegQuality: 85);
    final a = PageEdits(crop: Quad.full(inset: 0.1));
    expect(path(a), path(PageEdits(crop: Quad.full(inset: 0.1))));
    expect(path(a), isNot(path(PageEdits(crop: Quad.full(inset: 0.2)))));
    expect(path(a), isNot(path(a.copyWith(filter: FilterType.bwPrint))));
    expect(path(a), isNot(path(a, size: 'full')));
  });

  test('the export page cache survives the launch clean-up, trimmed oldest first', () async {
    final dir = Directory(p.dirname(files.exportPagePath('p', original, const PageEdits(), sizeKey: 's', jpegQuality: 85)));
    final old = File(p.join(dir.path, 'old.jpg'))..writeAsBytesSync(List.filled(600, 0));
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
    final recent = File(p.join(dir.path, 'recent.jpg'))..writeAsBytesSync(List.filled(600, 0));
    await files.clearExportTemp();
    expect(old.existsSync() && recent.existsSync(), isTrue);
    await files.trimExportCache(maxBytes: 1000);
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
    await files.clearCaches();
    expect(recent.existsSync(), isFalse, reason: 'Settings → clear cache empties it');
  });

  test('editor caches still match after Done moves the original (round 6)', () async {
    final edits = PageEdits(crop: Quad.full(inset: 0.1));
    final look = files.lookPath('p1', original, edits);
    final work = files.workPath('p1', original, edits);
    final moved = await files.adoptOriginal(sourcePath: original, docId: 'd1', pageId: 'p1');
    expect(moved, isNot(original));
    expect(files.lookPath('p1', moved, edits), look);
    expect(files.workPath('p1', moved, edits), work);
    // A retake (new content) gets new names.
    File(moved).writeAsBytesSync([1, 2, 3]);
    expect(files.lookPath('p1', moved, edits), isNot(look));
  });

  test('discardExportFiles removes staging folders, never cached renders', () async {
    final staging = files.exportPath('ready_x');
    Directory(staging).createSync(recursive: true);
    final shared = File(p.join(staging, 'doc.pdf'))..writeAsBytesSync([1]);
    final cached = File(files.exportPagePath('p1', original, const PageEdits(), sizeKey: 'standard', jpegQuality: 85))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([2]);
    await files.discardExportFiles([shared.path, cached.path]);
    expect(Directory(staging).existsSync(), isFalse);
    expect(cached.existsSync(), isTrue);
    expect(Directory(files.exportPath('')).existsSync(), isTrue, reason: 'the export root stays');
  });
}
