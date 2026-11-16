import 'dart:async';
import 'dart:io';

import 'package:flash_dox/app/theme/app_theme.dart';
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
import 'package:flash_dox/features/editor/presentation/pages/enhance_page.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

/// P0-3: while Enhance loads, nothing on screen is the uncropped photo or the
/// uncropped base preview; since round 6 (P0-2) not the raw crop either, but
/// an instant cleaned and filtered image.
void main() {
  late Directory tmp;
  late FileStore files;
  late _Proc proc;
  late ScanPage page;
  late CleanBaseService bases;

  setUpAll(() {
    registerFallbackValue(const PageEdits());
    registerFallbackValue(RenderSize.preview);
    registerFallbackValue(JobPriority.background);
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('never_raw');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    proc = _Proc();
    SharedPreferences.setMockInitialValues({});
    bases = CleanBaseService(proc, files, DeviceProfile(), PrefsService(await SharedPreferences.getInstance()));
    final original = files.newCapturePath('orig');
    final jpeg = File('test/fixtures/edges/box_colors_photo.jpg').readAsBytesSync();
    File(original).writeAsBytesSync(jpeg);
    page = ScanPage(id: 'p1', documentId: '', originalPath: original, edits: PageEdits(crop: Quad.full(inset: 0.1)), order: 0);
    File(files.basePreviewPath(page.id, original)).writeAsBytesSync(jpeg);
    String write(Invocation inv) {
      final out = inv.namedArguments[#outputPath] as String;
      File(out)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(jpeg);
      return out;
    }

    when(() => proc.renderQuick(any(), any(), outputPath: any(named: 'outputPath'))).thenAnswer((inv) async => write(inv));
    when(
      () => proc.renderInstantLook(any(), any(), workPath: any(named: 'workPath'), outputPath: any(named: 'outputPath'), cancel: any(named: 'cancel')),
    ).thenAnswer((inv) async => write(inv));
    // The cleaned base never finishes: the screen stays on the instant image.
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
    when(
      () => proc.renderFilterStrip(any(), any(), outputs: any(named: 'outputs')),
    ).thenAnswer((_) => Completer<void>().future);
  });

  tearDown(() => tmp.delete(recursive: true));

  testWidgets('Enhance shows the instant cleaned image, never the raw photo', (tester) async {
    final args = EditorArgs(pages: [page], mode: ScanMode.document);
    final bloc = PageEditorBloc(proc, files, _Create(), _Add(), _Update(), _Log(), _Render(), _Prepare(), PreviewCache(proc, files), _Namer(), bases, args)
      ..add(EditorStarted(args));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EnhancePage(bloc: bloc),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final shown = [
      for (final img in tester.widgetList<Image>(find.byType(Image)))
        if (img.image case FileImage(:final file)) file.path
        else if (img.image case ResizeImage(imageProvider: FileImage(:final file))) file.path,
    ];
    expect(shown, contains(files.instantLookPath(page.id, page.originalPath, page.edits)));
    expect(shown, isNot(contains(files.quickPath(page.id, page.originalPath, page.edits))));
    expect(shown, isNot(contains(page.originalPath)));
    expect(shown, isNot(contains(files.basePreviewPath(page.id, page.originalPath))));
    await tester.pumpWidget(const SizedBox());
    // Not awaited: the stubbed render never finishes.
    unawaited(bloc.close());
  });
}
