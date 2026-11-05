import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flutter_test/flutter_test.dart';
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
    return PageEditorBloc(proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), args)..add(EditorStarted(args));
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
}
