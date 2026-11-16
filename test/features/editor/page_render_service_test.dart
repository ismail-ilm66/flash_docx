import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
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

class _Proc extends Mock implements ImageProcessor {}

class _Repo extends Mock implements DocumentRepository {}

void main() {
  late Directory tmp;
  late FileStore files;
  late _Proc proc;
  late PageRenderService service;
  late ScanPage page;

  setUpAll(() {
    registerFallbackValue(const PageEdits());
    registerFallbackValue(RenderSize.standard);
    registerFallbackValue(JobPriority.background);
    registerFallbackValue(
      const ScanPage(id: '', documentId: '', originalPath: '', edits: PageEdits(), order: 0),
    );
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('page_render');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    final original = files.newCapturePath('orig');
    File(original).writeAsBytesSync([1]);
    page = ScanPage(
      id: 'p1',
      documentId: 'd1',
      originalPath: original,
      edits: PageEdits(crop: Quad.full(inset: 0.1)),
      order: 0,
    );
    proc = _Proc();
    final repo = _Repo();
    when(() => repo.updatePage(any())).thenAnswer((_) async => const Right(unit));
    service = PageRenderService(proc, files, repo);
    when(
      () => proc.render(
        any(),
        any(),
        size: any(named: 'size'),
        outputPath: any(named: 'outputPath'),
        jpegQuality: any(named: 'jpegQuality'),
        priority: any(named: 'priority'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((inv) async {
      final out = inv.namedArguments[#outputPath] as String;
      File(out)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([2]);
      return out;
    });
    when(
      () => proc.renderPageCaches(
        any(),
        any(),
        processedOut: any(named: 'processedOut'),
        thumbOut: any(named: 'thumbOut'),
      ),
    ).thenAnswer((inv) async {
      for (final k in [#processedOut, #thumbOut]) {
        File(inv.namedArguments[k] as String)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync([3]);
      }
    });
  });

  tearDown(() => tmp.delete(recursive: true));

  ScanDocument doc() => ScanDocument(
    id: 'd1',
    title: 'Doc',
    mode: ScanMode.document,
    pages: [page],
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  String exportPath() => files.exportPagePath(
    page.id,
    page.originalPath,
    page.edits,
    sizeKey: RenderSize.standard.name,
    jpegQuality: Limits.standardJpegQuality,
  );

  group('viewer caches', () {
    test('reuse the Enhance look instead of filtering the original again', () async {
      final look = files.lookPath(page.id, page.originalPath, page.edits);
      File(look).writeAsBytesSync([7, 7]);
      final updated = await service.ensurePageCache(page);
      expect(File(updated.processedPath!).readAsBytesSync(), [7, 7]);
      expect(File(updated.thumbPath!).existsSync(), isTrue);
      final thumbEdits = verify(
        () => proc.render(
          any(),
          captureAny(),
          size: RenderSize.thumb,
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).captured.single as PageEdits;
      expect(thumbEdits.filter, FilterType.original, reason: 'the look is filtered already');
      verifyNever(
        () => proc.renderPageCaches(
          any(),
          any(),
          processedOut: any(named: 'processedOut'),
          thumbOut: any(named: 'thumbOut'),
        ),
      );
    });

    test('render from the original when the look leaves something out', () async {
      page = page.withEdits(page.edits.copyWith(brightness: 20));
      File(files.lookPath(page.id, page.originalPath, page.edits)).writeAsBytesSync([7]);
      final updated = await service.ensurePageCache(page);
      expect(File(updated.processedPath!).readAsBytesSync(), [3]);
    });
  });

  group('Share and the warm-up render', () {
    test('a running warm-up render is awaited, not done twice', () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      when(
        () => proc.render(
          any(),
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).thenAnswer((inv) async {
        started.complete();
        await finish.future; // "running": cancelling no longer stops it
        final out = inv.namedArguments[#outputPath] as String;
        File(out).writeAsBytesSync([2]);
        return out;
      });
      final warm = service.warmExportPages(doc());
      await started.future;
      var joined = false;
      final join = service.joinWarm(exportPath()).then((v) => joined = v);
      await Future<void>.delayed(Duration.zero);
      expect(joined, isFalse, reason: 'waits for the running render');
      finish.complete();
      await Future.wait([warm, join]);
      expect(joined, isTrue);
      expect(File(exportPath()).existsSync(), isTrue);
    });

    test('a queued warm-up render is dropped for the Share to render', () async {
      CancelToken? token;
      when(
        () => proc.render(
          any(),
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).thenAnswer((inv) async {
        token = inv.namedArguments[#cancel] as CancelToken?;
        // "Queued": like IsolateRunner, a cancel before the start drops it.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (token?.isCancelled ?? false) throw const JobCancelled();
        return inv.namedArguments[#outputPath] as String;
      });
      final warm = service.warmExportPages(doc());
      await Future<void>.delayed(Duration.zero);
      expect(await service.joinWarm(exportPath()), isFalse);
      expect(token?.isCancelled, isTrue);
      await warm;
    });

    test('nothing warming: just whether the file exists', () async {
      expect(await service.joinWarm(exportPath()), isFalse);
    });
  });
}
