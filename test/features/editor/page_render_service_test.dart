import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/device_profile.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/clean_base_service.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
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

class _Proc extends Mock implements ImageProcessor {}

class _Repo extends Mock implements DocumentRepository {}

void _write(String path, List<int> bytes) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsBytesSync(bytes);

void main() {
  late Directory tmp;
  late FileStore files;
  late _Proc proc;
  late CleanBaseService bases;
  late PageRenderService service;
  late ScanPage page;

  /// Cleaned-base jobs started, and how each was answered.
  late int cleanJobs;
  late Future<void> Function(Invocation) cleanJob;

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
    SharedPreferences.setMockInitialValues({});
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
    bases = CleanBaseService(proc, files, DeviceProfile(), PrefsService(await SharedPreferences.getInstance()));
    service = PageRenderService(proc, files, repo, bases);
    cleanJobs = 0;
    cleanJob = (_) async {};
    when(
      () => proc.renderCleanBase(
        any(),
        any(),
        longEdge: any(named: 'longEdge'),
        outputPath: any(named: 'outputPath'),
        previewPath: any(named: 'previewPath'),
        card: any(named: 'card'),
        quick: any(named: 'quick'),
        priority: any(named: 'priority'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((inv) async {
      cleanJobs++;
      await cleanJob(inv);
      final out = inv.namedArguments[#outputPath] as String;
      _write(out, [5]);
      _write(inv.namedArguments[#previewPath] as String, [6]);
      return out;
    });
    for (final stub in [
      () => proc.render(
        any(),
        any(),
        size: any(named: 'size'),
        outputPath: any(named: 'outputPath'),
        jpegQuality: any(named: 'jpegQuality'),
        priority: any(named: 'priority'),
        cancel: any(named: 'cancel'),
      ),
      () => proc.renderFromClean(
        any(),
        any(),
        outputPath: any(named: 'outputPath'),
        maxLongEdge: any(named: 'maxLongEdge'),
        jpegQuality: any(named: 'jpegQuality'),
        priority: any(named: 'priority'),
        cancel: any(named: 'cancel'),
      ),
    ]) {
      when(stub).thenAnswer((inv) async {
        final out = inv.namedArguments[#outputPath] as String;
        _write(out, [2]);
        return out;
      });
    }
    when(
      () => proc.renderPageCaches(
        any(),
        any(),
        processedOut: any(named: 'processedOut'),
        thumbOut: any(named: 'thumbOut'),
      ),
    ).thenAnswer((inv) async {
      for (final k in [#processedOut, #thumbOut]) {
        _write(inv.namedArguments[k] as String, [3]);
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
    'd1',
    page.id,
    page.originalPath,
    page.edits,
    sizeKey: RenderSize.standard.name,
    jpegQuality: Limits.standardJpegQuality,
  );

  void neverFiltersTheOriginal() => verifyNever(
    () => proc.renderPageCaches(
      any(),
      any(),
      processedOut: any(named: 'processedOut'),
      thumbOut: any(named: 'thumbOut'),
    ),
  );

  group('viewer caches', () {
    test('reuse the Enhance look instead of filtering the original again', () async {
      _write(files.lookPath(page.id, page.originalPath, page.edits), [7, 7]);
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
      neverFiltersTheOriginal();
      expect(cleanJobs, 0);
    });

    test('otherwise come from the cleaned base, sliders included (round 6)', () async {
      page = page.withEdits(page.edits.copyWith(brightness: 20));
      final updated = await service.ensurePageCache(page);
      expect(File(updated.processedPath!).readAsBytesSync(), [2]);
      expect(cleanJobs, 1);
      neverFiltersTheOriginal();
    });

    test('Original (the raw page) still renders from the original', () async {
      page = page.withEdits(page.edits.copyWith(filter: FilterType.original));
      final updated = await service.ensurePageCache(page);
      expect(File(updated.processedPath!).readAsBytesSync(), [3]);
      expect(cleanJobs, 0);
    });
  });

  group('Share and the warm-up render', () {
    test('every export page comes from the one cleaned base', () async {
      await service.warmExportPages(doc());
      expect(File(exportPath()).existsSync(), isTrue);
      await service.renderExportPage(
        page,
        size: RenderSize.standard,
        outputPath: p.join(tmp.path, 'share.jpg'),
        jpegQuality: 85,
        card: false,
      );
      await service.ensurePageCache(page);
      expect(cleanJobs, 1, reason: 'cleaned once, used three times');
    });

    test('a running warm-up render is awaited, not done twice', () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      cleanJob = (_) async {
        started.complete();
        await finish.future; // running: cancelling no longer stops it
      };
      final warm = service.warmExportPages(doc());
      await started.future;
      var joined = false;
      final join = service.joinWarm(exportPath()).then((v) => joined = v);
      await Future<void>.delayed(Duration.zero);
      expect(joined, isFalse, reason: 'waits for the running render');
      finish.complete();
      await Future.wait([warm, join]);
      expect(joined, isTrue);
      expect(cleanJobs, 1);
    });

    test('nothing warming: just whether the file exists', () async {
      expect(await service.joinWarm(exportPath()), isFalse);
    });
  });

  group('CleanBaseService', () {
    test('a second caller joins the job instead of starting another', () async {
      final finish = Completer<void>();
      cleanJob = (_) => finish.future;
      final a = bases.ensure(page, card: false);
      final b = bases.ensure(page, card: false);
      finish.complete();
      expect(await a, await b);
      expect(cleanJobs, 1);
    });

    test('an interactive caller moves a queued background job up', () async {
      final priorities = <JobPriority>[];
      cleanJob = (inv) async {
        final token = inv.namedArguments[#cancel] as CancelToken;
        priorities.add(inv.namedArguments[#priority] as JobPriority);
        // "Queued": a cancel before the start drops it, as IsolateRunner does.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (token.isCancelled) throw const JobCancelled();
      };
      final background = bases.ensure(page, card: false);
      await Future<void>.delayed(Duration.zero);
      final interactive = bases.ensure(page, card: false, priority: JobPriority.interactive);
      expect(await interactive, isNotEmpty);
      expect(await background, await interactive, reason: 'the first caller gets it too');
      expect(priorities, [JobPriority.background, JobPriority.interactive]);
    });

    test('a deleted page drops its queued job', () async {
      cleanJob = (inv) async {
        final token = inv.namedArguments[#cancel] as CancelToken;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (token.isCancelled) throw const JobCancelled();
      };
      final job = bases.ensure(page, card: false);
      bases.cancel(page.id);
      await expectLater(job, throwsA(isA<JobCancelled>()));
    });

    test('2000 px by default, 2400 for High, never above 2000 on a low-RAM phone', () async {
      expect(bases.longEdgeFor(), 2000);
      expect(bases.longEdgeFor(high: true), 2400);
      final low = DeviceProfile()..debugSet(totalBytes: 2 << 30);
      final lowRam = CleanBaseService(proc, files, low, PrefsService(await SharedPreferences.getInstance()));
      expect(lowRam.longEdgeFor(high: true), 2000);
    });
  });

  group('round 10, P0-3: display images', () {
    test('1600 px, q85, from the cleaned base; thumbnail q80', () async {
      await service.ensurePageCache(page);
      verify(
        () => proc.renderFromClean(
          any(),
          any(),
          outputPath: any(named: 'outputPath'),
          maxLongEdge: RenderPx.displayLongEdge,
          jpegQuality: Limits.displayJpegQuality,
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).called(1);
      verify(
        () => proc.render(
          any(),
          any(),
          size: RenderSize.thumb,
          outputPath: any(named: 'outputPath'),
          jpegQuality: Limits.thumbJpegQuality,
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).called(1);
      expect(RenderPx.displayLongEdge, 1600);
    });

    test("a base the editor already made is used before Enhance's smaller look", () async {
      _write(bases.basePath(page, card: false), [5]);
      _write(files.lookPath(page.id, page.originalPath, page.edits), [7, 7]);
      final updated = await service.ensurePageCache(page);
      expect(File(updated.processedPath!).readAsBytesSync(), [2], reason: 'rendered from the base, not the 1200 px look');
      expect(cleanJobs, 0);
    });

    test('the page on screen first', () async {
      final order = <String>[];
      when(
        () => proc.renderCleanBase(
          any(),
          any(),
          longEdge: any(named: 'longEdge'),
          outputPath: any(named: 'outputPath'),
          previewPath: any(named: 'previewPath'),
          card: any(named: 'card'),
          quick: any(named: 'quick'),
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).thenAnswer((inv) async {
        order.add(p.basename(inv.namedArguments[#outputPath] as String).split('_')[1]);
        final out = inv.namedArguments[#outputPath] as String;
        _write(out, [5]);
        _write(inv.namedArguments[#previewPath] as String, [6]);
        return out;
      });
      final second = page.copyWith(id: 'p2', order: 1);
      final third = page.copyWith(id: 'p3', order: 2);
      final d = doc().copyWith(mode: ScanMode.idCard, pages: [page, second, third]);
      await service.ensureCaches(d, first: 'p3');
      expect(order, ['p3', 'p1', 'p2']);
    });
  });
}
