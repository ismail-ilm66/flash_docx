import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
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
  late _Proc proc;
  late ScanPage page;

  setUpAll(() {
    registerFallbackValue(const PageEdits());
    registerFallbackValue(RenderSize.preview);
    registerFallbackValue(ScanMode.document);
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
    when(() => proc.render(any(), any(), size: any(named: 'size'), outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality')))
        .thenAnswer((inv) async => inv.namedArguments[#outputPath] as String);
    when(() => proc.renderLook(any(), any(), workPath: any(named: 'workPath'), outputPath: any(named: 'outputPath')))
        .thenAnswer((inv) async => inv.namedArguments[#outputPath] as String);
  });

  tearDown(() => tmp.delete(recursive: true));

  PageEditorBloc build() {
    final args = EditorArgs(pages: [page], mode: ScanMode.document);
    return PageEditorBloc(proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), _Prepare(), args)..add(EditorStarted(args));
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 200));

  test('reuses the base preview written by ingest instead of rendering it', () async {
    final base = files.basePreviewPath(page.id, page.originalPath);
    File(base).writeAsBytesSync([1]);
    final bloc = build();
    await settle();
    expect(bloc.state.basePreview, base);
    verifyNever(() => proc.render(any(), any(), size: any(named: 'size'), outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality')));
    await bloc.close();
  });

  test('renders the base preview when it is missing', () async {
    final bloc = build();
    await settle();
    expect(bloc.state.basePreview, files.basePreviewPath(page.id, page.originalPath));
    verify(() => proc.render(any(), any(), size: RenderSize.preview, outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality'))).called(1);
    await bloc.close();
  });

  test('sliders update edits without any new render; a filter change renders once', () async {
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
    verifyNever(() => proc.renderLook(any(), any(), workPath: any(named: 'workPath'), outputPath: any(named: 'outputPath')));

    bloc.add(const EditorFilterChanged(FilterType.bwPrint));
    await settle();
    verify(() => proc.renderLook(any(), any(), workPath: any(named: 'workPath'), outputPath: any(named: 'outputPath'))).called(1);
    await bloc.close();
  });

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

  test('P0-3: retaking page 2 of an ID scan keeps its side, place, card shape and look', () async {
    final prepare = _Prepare();
    final front = page.copyWith(id: 'front', side: CardSide.front, order: 0);
    final back = page.copyWith(
      id: 'back',
      side: CardSide.back,
      order: 1,
      edits: const PageEdits(filter: FilterType.bwPrint, brightness: 12, outputAspect: 85.6 / 54),
    );
    const args = EditorArgs(pages: [], mode: ScanMode.idCard);
    final bloc = PageEditorBloc(
      proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), prepare,
      EditorArgs(pages: [front, back], mode: args.mode, initialIndex: 1),
    );
    const guide = Quad(tl: Pt(0.1, 0.3), tr: Pt(0.9, 0.3), br: Pt(0.9, 0.6), bl: Pt(0.1, 0.6));
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
        turns: any(named: 'turns'),
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
          edits: const PageEdits(crop: guide, filter: FilterType.idColor, outputAspect: 85.6 / 54, quarterTurns: 2),
          order: 0,
          side: (inv.namedArguments[#sides] as List<CardSide?>).single,
        ),
      ]),
    );

    bloc.add(const EditorPageRetaken('placeholder', guide: guide, turns: 3));
    await settle();
    // The event carries the raw shot; use a real file for the call check.
    final call = verify(
      () => prepare(
        captureAny(),
        mode: captureAny(named: 'mode'),
        sides: captureAny(named: 'sides'),
        fallbacks: captureAny(named: 'fallbacks'),
        turns: captureAny(named: 'turns'),
        ids: captureAny(named: 'ids'),
        copySource: any(named: 'copySource'),
        onPrepared: any(named: 'onPrepared'),
      ),
    )..called(1);
    expect(call.captured[1], ScanMode.idCard, reason: 'same mode');
    expect(call.captured[2], [CardSide.back], reason: 'same side');
    expect(call.captured[3], [guide], reason: 'guide fallback passed on');
    expect(call.captured[4], [3], reason: 'phone orientation passed on');
    expect(call.captured[5], ['back'], reason: 'same page id');

    expect(bloc.state.index, 1);
    final p2 = bloc.state.pages[1];
    expect(p2.id, 'back');
    expect(p2.side, CardSide.back);
    expect(p2.originalPath, fresh);
    expect(p2.edits.outputAspect, closeTo(85.6 / 54, 1e-9), reason: 'card shape');
    expect(p2.edits.quarterTurns, 2, reason: 'auto-orientation of the new photo');
    expect(p2.edits.filter, FilterType.bwPrint, reason: 'look kept');
    expect(p2.edits.brightness, 12);
    expect(bloc.state.pages[0].id, 'front', reason: 'other page untouched');
    await bloc.close();
  });
}
