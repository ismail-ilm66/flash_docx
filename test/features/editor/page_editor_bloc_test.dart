import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/data/services/smart_namer.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
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
      args,
    )..add(EditorStarted(args));
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

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
        () => proc.renderLook(
          any(),
          any(),
          workPath: any(named: 'workPath'),
          autoBasePath: any(named: 'autoBasePath'),
          priority: any(named: 'priority'),
          outputPath: any(named: 'outputPath'),
          cancel: any(named: 'cancel'),
        ),
      );

      bloc.add(const EditorFilterChanged(FilterType.bwPrint));
      await settle();
      verify(
        () => proc.renderLook(
          any(),
          any(),
          workPath: any(named: 'workPath'),
          autoBasePath: any(named: 'autoBasePath'),
          priority: any(named: 'priority'),
          outputPath: any(named: 'outputPath'),
          cancel: any(named: 'cancel'),
        ),
      ).called(1);
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
      final oldLook = bloc.state.shownPreview;
      expect(oldLook, files.lookPath(page.id, page.originalPath, page.edits));
      // The new crop's filtered render never finishes: only its placeholder.
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
      ).thenAnswer((_) => Completer<String>().future);
      bloc
        ..add(EditorCropChanged(Quad.full(inset: 0.2)))
        ..add(const EditorCornerDragEnded());
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final cur = bloc.state.current!;
      expect(
        bloc.state.shownPreview,
        files.quickPath(cur.id, cur.originalPath, cur.edits),
        reason: "the new crop's placeholder, rendered on its own after the drag",
      );
      await bloc.close();
    },
  );

  test(
    'P0-4: Enhance shows the crop-only placeholder, never the uncropped photo',
    () async {
      final bloc = build();
      await settle();
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

  test('P0-3: the Adjust strip gets a crop-only preview for every page', () async {
    final second = page.copyWith(id: 'p2', order: 1);
    final args = EditorArgs(pages: [page, second], mode: ScanMode.document);
    final bloc = PageEditorBloc(proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), _Prepare(), PreviewCache(proc, files), _Namer(), args)
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
