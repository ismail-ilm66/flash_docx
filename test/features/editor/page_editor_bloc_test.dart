import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/services/device_profile.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/data/services/smart_namer.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/clean_base_service.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Proc extends Mock implements ImageProcessor {}

class _Create extends Mock implements CreateDocument {}

class _Add extends Mock implements AddPages {}

class _Update extends Mock implements UpdatePages {}

class _Log extends Mock implements LogActivity {}

class _Render extends Mock implements PageRenderService {}

class _Prepare extends Mock implements PreparePages {}

class _Namer extends Mock implements SmartNamer {}

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

void main() {
  late Directory tmp;
  late FileStore files;
  late _Proc proc;
  late ScanPage page;
  late CleanBaseService bases;

  /// Cleaned-base jobs started.
  late int cleanJobs;

  setUpAll(() {
    registerFallbackValue(const PageEdits());
    registerFallbackValue(RenderSize.preview);
    registerFallbackValue(ScanMode.document);
    registerFallbackValue(JobPriority.background);
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('editor_bloc');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    proc = _Proc();
    SharedPreferences.setMockInitialValues({});
    bases = CleanBaseService(proc, files, DeviceProfile(), PrefsService(await SharedPreferences.getInstance()));
    cleanJobs = 0;
    String write(Invocation inv, [Symbol key = #outputPath]) {
      final out = inv.namedArguments[key] as String;
      File(out)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([1]);
      return out;
    }

    when(
      () => proc.renderInstantLook(any(), any(), workPath: any(named: 'workPath'), outputPath: any(named: 'outputPath'), cancel: any(named: 'cancel')),
    ).thenAnswer((inv) async => write(inv));
    when(
      () => proc.renderLookFromClean(
        any(),
        any(),
        outputPath: any(named: 'outputPath'),
        autoPath: any(named: 'autoPath'),
        priority: any(named: 'priority'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((inv) async => write(inv));
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
      write(inv, #previewPath);
      return write(inv);
    });
    final original = files.newCapturePath('orig');
    File(original).writeAsBytesSync([1]);
    page = ScanPage(
      id: 'p1',
      documentId: '',
      originalPath: original,
      edits: PageEdits(crop: Quad.full(inset: 0.1)),
      order: 0,
    );
    when(
      () => proc.render(
        any(),
        any(),
        size: any(named: 'size'),
        outputPath: any(named: 'outputPath'),
        jpegQuality: any(named: 'jpegQuality'),
        priority: any(named: 'priority'),
      ),
    ).thenAnswer((inv) async => inv.namedArguments[#outputPath] as String);
    when(
      () => proc.renderLook(
        any(),
        any(),
        workPath: any(named: 'workPath'),
        autoBasePath: any(named: 'autoBasePath'),
        priority: any(named: 'priority'),
        outputPath: any(named: 'outputPath'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((inv) async => inv.namedArguments[#outputPath] as String);
    when(
      () =>
          proc.renderQuick(any(), any(), outputPath: any(named: 'outputPath')),
    ).thenAnswer((inv) async {
      final out = inv.namedArguments[#outputPath] as String;
      File(out).writeAsBytesSync([1]);
      return out;
    });
  });

  tearDown(() => tmp.delete(recursive: true));

  PageEditorBloc build() {
    final args = EditorArgs(pages: [page], mode: ScanMode.document);
    return PageEditorBloc(
      proc,
      files,
      _Create(),
      _Add(),
      _Update(),
      _Log(),
      _Render(),
      _Prepare(),
      PreviewCache(proc, files),
      _Namer(),
      bases,
      args,
    )..add(EditorStarted(args));
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  /// Next on Adjust edges: Enhance opens.
  Future<void> enhance(PageEditorBloc bloc) async {
    bloc.add(const EditorPreviewRequested(forEnhance: true));
    await settle();
  }

  void verifyLooks(int n) {
    Future<String> look() => proc.renderLookFromClean(
      any(),
      any(),
      outputPath: any(named: 'outputPath'),
      autoPath: any(named: 'autoPath'),
      priority: any(named: 'priority'),
      cancel: any(named: 'cancel'),
    );
    if (n == 0) {
      verifyNever(look);
    } else {
      verify(look).called(n);
    }
  }

  test(
    'reuses the base preview written by ingest instead of rendering it',
    () async {
      final base = files.basePreviewPath(page.id, page.originalPath);
      File(base).writeAsBytesSync([1]);
      final bloc = build();
      await settle();
      expect(bloc.state.basePreview, base);
      verifyNever(
        () => proc.render(
          any(),
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
          priority: any(named: 'priority'),
        ),
      );
      await bloc.close();
    },
  );

  test('renders the base preview when it is missing', () async {
    final bloc = build();
    await settle();
    expect(
      bloc.state.basePreview,
      files.basePreviewPath(page.id, page.originalPath),
    );
    verify(
      () => proc.render(
        any(),
        any(),
        size: RenderSize.preview,
        outputPath: any(named: 'outputPath'),
        jpegQuality: any(named: 'jpegQuality'),
        priority: any(named: 'priority'),
      ),
    ).called(1);
    await bloc.close();
  });

  test(
    'sliders update edits without any new render; a filter change renders once',
    () async {
      final bloc = build();
      await settle();
      await enhance(bloc);
      clearInteractions(proc);
      for (var v = 1; v <= 20; v++) {
        bloc
          ..add(EditorBrightnessChanged(v * 3.0))
          ..add(EditorContrastChanged(-v * 2.0));
      }
      await settle();
      expect(bloc.state.edits.brightness, 60);
      expect(bloc.state.edits.contrast, -40);
      verifyNever(
        () => proc.renderLookFromClean(
          any(),
          any(),
          outputPath: any(named: 'outputPath'),
          autoPath: any(named: 'autoPath'),
          priority: any(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      );

      bloc.add(const EditorFilterChanged(FilterType.bwPrint));
      await settle();
      // From the cleaned base made when Enhance opened: no new clean-up.
      verifyLooks(1);
      expect(cleanJobs, 1);
      await bloc.close();
    },
  );

  test('a corner drag that would bend the crop is rejected', () async {
    final bloc = build();
    await settle();
    final before = bloc.state.edits.crop;
    // Drag bottom-right past the top-left corner.
    bloc.add(const EditorCornerMoved(2, Pt(0.05, 0.05)));
    await settle();
    expect(bloc.state.edits.crop, before);
    // A normal drag is accepted.
    bloc.add(const EditorCornerMoved(2, Pt(0.85, 0.88)));
    await settle();
    expect(bloc.state.edits.crop!.br, const Pt(0.85, 0.88));
    await bloc.close();
  });

  test(
    'P0-3: retaking page 2 of an ID scan keeps its side, place, card shape and look',
    () async {
      final prepare = _Prepare();
      final front = page.copyWith(id: 'front', side: CardSide.front, order: 0);
      final back = page.copyWith(
        id: 'back',
        side: CardSide.back,
        order: 1,
        edits: const PageEdits(
          filter: FilterType.bwPrint,
          brightness: 12,
          outputAspect: 85.6 / 54,
        ),
      );
      const args = EditorArgs(pages: [], mode: ScanMode.idCard);
      final bloc = PageEditorBloc(
        proc,
        files,
        _Create(),
        _Add(),
        _Update(),
        _Log(),
        _Render(),
        prepare,
        PreviewCache(proc, files),
        _Namer(),
        bases,
        EditorArgs(pages: [front, back], mode: args.mode, initialIndex: 1),
      );
      const guide = Quad(
        tl: Pt(0.1, 0.3),
        tr: Pt(0.9, 0.3),
        br: Pt(0.9, 0.6),
        bl: Pt(0.1, 0.6),
      );
      final shot = files.newCapturePath('retake_raw');
      File(shot).writeAsBytesSync([1]);
      final fresh = files.newCapturePath('back_new');
      File(fresh).writeAsBytesSync([1]);
      when(
        () => prepare(
          any(),
          mode: any(named: 'mode'),
          sides: any(named: 'sides'),
          fallbacks: any(named: 'fallbacks'),
          captures: any(named: 'captures'),
          ids: any(named: 'ids'),
          copySource: any(named: 'copySource'),
          onPrepared: any(named: 'onPrepared'),
        ),
      ).thenAnswer(
        (inv) async => Right([
          ScanPage(
            id: (inv.namedArguments[#ids] as List<String>).single,
            documentId: '',
            originalPath: fresh,
            edits: const PageEdits(
              crop: guide,
              filter: FilterType.idColor,
              outputAspect: 85.6 / 54,
              quarterTurns: 2,
            ),
            order: 0,
            side: (inv.namedArguments[#sides] as List<CardSide?>).single,
          ),
        ]),
      );

      const capture = CaptureMeta(sensorOrientation: 90, deviceTurns: 3);
      bloc.add(const EditorPageRetaken('placeholder', guide: guide, capture: capture));
      await settle();
      // The event carries the raw shot; use a real file for the call check.
      final call = verify(
        () => prepare(
          captureAny(),
          mode: captureAny(named: 'mode'),
          sides: captureAny(named: 'sides'),
          fallbacks: captureAny(named: 'fallbacks'),
          captures: captureAny(named: 'captures'),
          ids: captureAny(named: 'ids'),
          copySource: any(named: 'copySource'),
          onPrepared: any(named: 'onPrepared'),
        ),
      )..called(1);
      expect(call.captured[1], ScanMode.idCard, reason: 'same mode');
      expect(call.captured[2], [CardSide.back], reason: 'same side');
      expect(call.captured[3], [guide], reason: 'guide fallback passed on');
      expect(call.captured[4], [capture], reason: 'what the camera knew is passed on');
      expect(call.captured[5], ['back'], reason: 'same page id');

      expect(bloc.state.index, 1);
      final p2 = bloc.state.pages[1];
      expect(p2.id, 'back');
      expect(p2.side, CardSide.back);
      expect(p2.originalPath, fresh);
      expect(
        p2.edits.outputAspect,
        closeTo(85.6 / 54, 1e-9),
        reason: 'card shape',
      );
      expect(
        p2.edits.quarterTurns,
        2,
        reason: 'auto-orientation of the new photo',
      );
      expect(p2.edits.filter, FilterType.bwPrint, reason: 'look kept');
      expect(p2.edits.brightness, 12);
      expect(bloc.state.pages[0].id, 'front', reason: 'other page untouched');
      await bloc.close();
    },
  );

  test(
    "after a crop, Enhance shows the new shape, never the old crop's look",
    () async {
      final bloc = build();
      await settle();
      await enhance(bloc);
      final oldLook = bloc.state.shownPreview;
      expect(oldLook, files.lookPath(page.id, page.originalPath, page.edits));
      // Back to Adjust edges; the new crop's cleaned base never finishes.
      bloc.add(const EditorEnhanceClosed());
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
      ).thenAnswer((_) => Completer<String>().future);
      clearInteractions(proc);
      bloc
        ..add(EditorCropChanged(Quad.full(inset: 0.2)))
        ..add(const EditorCornerDragEnded());
      await settle();
      // Moving the corners renders nothing (a render can't be stopped once
      // started).
      verifyNever(() => proc.renderQuick(any(), any(), outputPath: any(named: 'outputPath')));
      await enhance(bloc);
      final cur = bloc.state.current!;
      expect(
        bloc.state.shownPreview,
        files.instantLookPath(cur.id, cur.originalPath, cur.edits),
        reason: "the new crop's instant image, not the old crop's look",
      );
      await bloc.close();
    },
  );

  test('round 6, P0-2: Adjust edges makes no look and no cleaned base', () async {
    final bloc = build();
    await settle();
    bloc.add(const EditorRotated(clockwise: true));
    await settle();
    expect(cleanJobs, 0);
    verifyNever(
      () => proc.renderInstantLook(any(), any(), workPath: any(named: 'workPath'), outputPath: any(named: 'outputPath'), cancel: any(named: 'cancel')),
    );
    verifyLooks(0);
    expect(bloc.state.quickPreviews[page.id], isNotNull, reason: 'the strip still gets its placeholder');
    await bloc.close();
  });

  test(
    'round 6, P0-2: Enhance shows an instant cleaned image, then the look from the cleaned base',
    () async {
      final release = Completer<void>();
      when(
        () => proc.renderCleanBase(
          any(),
          any(),
          longEdge: any(named: 'longEdge'),
          outputPath: any(named: 'outputPath'),
          previewPath: any(named: 'previewPath'),
          card: any(named: 'card'),
          quick: any(named: 'quick'),
          priority: captureAny(named: 'priority'),
          cancel: any(named: 'cancel'),
        ),
      ).thenAnswer((inv) async {
        cleanJobs++;
        await release.future;
        for (final k in [#outputPath, #previewPath]) {
          File(inv.namedArguments[k] as String).writeAsBytesSync([1]);
        }
        return inv.namedArguments[#outputPath] as String;
      });
      final bloc = build();
      await settle();
      await enhance(bloc);
      expect(bloc.state.shownPreview, files.instantLookPath(page.id, page.originalPath, page.edits));
      expect(bloc.state.shownPreview, isNot(bloc.state.comparePreview), reason: 'never the raw crop');
      expect(bloc.state.rendering, isTrue);
      release.complete();
      await settle();
      expect(bloc.state.shownPreview, files.lookPath(page.id, page.originalPath, page.edits));
      expect(bloc.state.rendering, isFalse);
      // A filter change, and back: one cleaned base for all of it.
      bloc.add(const EditorFilterChanged(FilterType.grayscale));
      await settle();
      bloc.add(const EditorFilterChanged(FilterType.auto));
      await settle();
      expect(cleanJobs, 1);
      expect(bloc.state.shownPreview, files.lookPath(page.id, page.originalPath, bloc.state.edits));
      await bloc.close();
    },
  );

  test(
    'P0-4: Enhance never shows the uncropped photo; compare shows the crop unfiltered',
    () async {
      final bloc = build();
      await settle();
      await enhance(bloc);
      final shown = bloc.state.shownPreview;
      expect(shown, isNotNull);
      expect(
        shown,
        isNot(bloc.state.basePreview),
        reason: 'base preview is the uncropped photo',
      );
      expect(shown, isNot(page.originalPath));
      expect(
        bloc.state.comparePreview,
        files.quickPath(page.id, page.originalPath, page.edits),
      );
      await bloc.close();
    },
  );

  group('P1-1 Enhance', () {
    PageEditorBloc buildTwo({String? documentId}) {
      final args = EditorArgs(
        pages: [
          page.copyWith(edits: page.edits.copyWith(filter: FilterType.auto)),
          page.copyWith(
            id: 'p2',
            order: 1,
            edits: page.edits.copyWith(filter: FilterType.auto),
          ),
        ],
        mode: ScanMode.document,
        documentId: documentId,
      );
      return PageEditorBloc(
        proc,
        files,
        _Create(),
        _Add(),
        _Update(),
        _Log(),
        _Render(),
        _Prepare(),
        PreviewCache(proc, files),
        _Namer(),
        bases,
        args,
      )..add(EditorStarted(args));
    }

    test(
      'a new scan starts with "All N pages" on: a filter goes to every page; Reset brings all back to Auto',
      () async {
        final bloc = buildTwo();
        await settle();
        expect(bloc.state.applyAll, isTrue);
        expect(bloc.state.canReset, isFalse, reason: 'already at the default');

        bloc
          ..add(const EditorFilterChanged(FilterType.bwPrint))
          ..add(const EditorBrightnessChanged(20));
        await settle();
        expect(bloc.state.pages.map((p) => p.edits.filter), [
          FilterType.bwPrint,
          FilterType.bwPrint,
        ]);
        expect(bloc.state.pages.map((p) => p.edits.brightness), [20, 20]);
        expect(bloc.state.canReset, isTrue);

        bloc.add(const EditorLookReset());
        await settle();
        expect(bloc.state.pages.map((p) => p.edits.filter), [
          FilterType.auto,
          FilterType.auto,
        ]);
        expect(bloc.state.pages.map((p) => p.edits.brightness), [0, 0]);
        expect(
          bloc.state.pages.first.edits.crop,
          page.edits.crop,
          reason: 'Reset never touches the crop',
        );
        expect(bloc.state.canReset, isFalse);
        await bloc.close();
      },
    );

    test(
      'editing a saved document starts with the switch off and changes only the current page',
      () async {
        final bloc = buildTwo(documentId: 'doc');
        await settle();
        expect(bloc.state.applyAll, isFalse);
        bloc.add(const EditorFilterChanged(FilterType.grayscale));
        await settle();
        expect(bloc.state.pages.map((p) => p.edits.filter), [
          FilterType.grayscale,
          FilterType.auto,
        ]);

        // Turning the switch on spreads the current look.
        bloc.add(const EditorApplyAllToggled(true));
        await settle();
        expect(bloc.state.pages.map((p) => p.edits.filter), [
          FilterType.grayscale,
          FilterType.grayscale,
        ]);
        await bloc.close();
      },
    );

    test('filter thumbnails render once per page look', () async {
      when(
        () => proc.renderFilterStrip(
          any(),
          any(),
          outputs: any(named: 'outputs'),
        ),
      ).thenAnswer((inv) async {
        for (final out
            in (inv.namedArguments[#outputs] as Map<FilterType, String>)
                .values) {
          File(out).writeAsBytesSync([1]);
        }
      });
      final bloc = build();
      await settle();
      bloc.add(const EditorFilterThumbsRequested());
      await settle();
      bloc.add(const EditorFilterThumbsRequested());
      await settle();
      final thumbs = bloc.state.filterThumbs[page.id]!;
      expect(thumbs.keys, FilterType.values);
      expect(thumbs.values.toSet().length, FilterType.values.length);
      verify(
        () => proc.renderFilterStrip(
          any(),
          any(),
          outputs: any(named: 'outputs'),
        ),
      ).called(1);
      await bloc.close();
    });
  });

  test('round 6, P1-1: a partly blurry shot offers a retake until Keep', () async {
    final args = EditorArgs(pages: [page], mode: ScanMode.document, blurryPages: {page.id});
    final bloc = PageEditorBloc(proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), _Prepare(), PreviewCache(proc, files), _Namer(), bases, args)
      ..add(EditorStarted(args));
    await settle();
    expect(bloc.state.currentBlurry, isTrue);
    bloc.add(const EditorBlurryKept());
    await settle();
    expect(bloc.state.currentBlurry, isFalse);
    await bloc.close();
  });

  test('P0-3: the Adjust strip gets a crop-only preview for every page', () async {
    final second = page.copyWith(id: 'p2', order: 1);
    final args = EditorArgs(pages: [page, second], mode: ScanMode.document);
    final bloc = PageEditorBloc(proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), _Prepare(), PreviewCache(proc, files), _Namer(), bases, args)
      ..add(EditorStarted(args));
    await settle();
    for (final pg in [page, second]) {
      final shown = bloc.state.quickPreviews[pg.id];
      expect(shown, files.quickPath(pg.id, pg.originalPath, pg.edits));
      expect(shown, isNot(bloc.state.basePreviews[pg.id]));
      expect(shown, isNot(pg.originalPath));
    }
    await bloc.close();
  });
}
