import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/app_router.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/ocr/presentation/pages/extracted_text_page.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_overlay.dart';
import 'package:flash_dox/features/settings/presentation/cubit/theme_cubit.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// P1-5: every screen's chrome at Android's largest font (2.0×) on a small
/// phone (360 × 740). Fails on any overflow (reported by Flutter itself) and
/// on any label cut off with an ellipsis.
class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
  @override
  Future<String?> getApplicationSupportPath() async => p.join(root.path, 'support');
}

/// Renders never finish, so every screen shows its loading state; the test
/// is about the chrome around the image.
class _PendingProcessor implements ImageProcessor {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

const _size = Size(360, 740);
final AppLocalizations l = lookupAppLocalizations(const Locale('en'));

/// The app's own font. Flutter tests otherwise draw every glyph as a 1 em
/// square, which makes every label far wider than on a phone.
Future<void> _loadAppFont() async {
  final loader = FontLoader(AppTheme.fontFamily);
  for (final w in [400, 500, 600, 700, 800]) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Manrope-$w.ttf').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await _loadAppFont();
  });
  late ScanDocument doc;
  late ScanDocument card;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('large_font');
    PathProviderPlatform.instance = _Paths(tmp);
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    await configureDependencies();
    getIt
      ..unregister<AppDatabase>()
      ..registerLazySingleton<AppDatabase>(() => AppDatabase.test(NativeDatabase.memory()))
      ..unregister<ImageProcessor>()
      ..registerLazySingleton<ImageProcessor>(_PendingProcessor.new);

    final files = getIt<FileStore>();
    // Never decoded (renders are stubbed); any JPEG will do.
    final jpeg = File('test/fixtures/edges/box_colors_photo.jpg').readAsBytesSync();
    ScanPage page(String id, int order, {CardSide? side}) {
      final path = files.newCapturePath(id);
      File(path).writeAsBytesSync(jpeg);
      return ScanPage(id: id, documentId: '', originalPath: path, edits: const PageEdits(), order: order, side: side);
    }

    final create = getIt<CreateDocument>();
    doc = (await create(mode: ScanMode.document, pages: [page('a', 0), page('b', 1), page('c', 2)], title: 'Lease'))
        .getOrElse((f) => throw StateError('$f'));
    card = (await create(
      mode: ScanMode.idCard,
      pages: [page('f', 0, side: CardSide.front), page('k', 1, side: CardSide.back)],
      title: 'ID card',
    ))
        .getOrElse((f) => throw StateError('$f'));
  });

  tearDown(() async {
    // The in-memory database is dropped, not closed: closing waits for
    // stream queries started inside the test's fake-async zone, which never
    // finish once the test body has returned.
    await getIt.reset(dispose: false);
    await tmp.delete(recursive: true);
  });

  Future<void> setUpView(WidgetTester tester) async {
    tester.view
      ..physicalSize = _size
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectNothingCutOff(WidgetTester tester, String screen) {
    final cut = {
      for (final r in tester.allRenderObjects.whereType<RenderParagraph>())
        if (!r.debugNeedsLayout && r.didExceedMaxLines && r.overflow == TextOverflow.ellipsis) '${r.text.toPlainText()} (${r.constraints.maxWidth.round()} px)',
    };
    expect(cut, isEmpty, reason: '$screen: labels cut off at 2× font');
  }

  Future<GoRouter> pumpApp(WidgetTester tester, {ThemeMode mode = ThemeMode.light}) async {
    await setUpView(tester);
    final router = buildRouter();
    await tester.pumpWidget(
      BlocProvider.value(
        value: getIt<ThemeCubit>(),
        child: MaterialApp.router(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    return router;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('Home', (tester) async {
    final router = await pumpApp(tester);
    router.go(Routes.home);
    await settle(tester);
    expectNothingCutOff(tester, 'Home');
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.textContaining(l.pagesCount(2)), 200, scrollable: list);
    await settle(tester);
    expectNothingCutOff(tester, 'Home, Tools and first document');
    await tester.scrollUntilVisible(find.text('Lease'), 200, scrollable: list);
    await settle(tester);
    expectNothingCutOff(tester, 'Home, scrolled');
    await close(tester);
  });

  testWidgets('Home › Tools › Pick a document', (tester) async {
    final router = await pumpApp(tester);
    router.go(Routes.home);
    await settle(tester);
    await tester.scrollUntilVisible(find.text(l.toolExtractText), 200, scrollable: find.byType(Scrollable).first);
    expectNothingCutOff(tester, 'Tools');
    await tester.tap(find.text(l.toolExtractText));
    await settle(tester);
    expect(find.text(l.pickDocumentTitle), findsOneWidget);
    // Newest first.
    final titles = tester.widgetList<DocumentTile>(find.byType(DocumentTile)).map((t) => t.document.title).toList();
    expect(titles.take(2), ['ID card', 'Lease']);
    expectNothingCutOff(tester, 'Pick a document');

    await tester.tap(find.descendant(of: find.byType(AppBottomSheet), matching: find.text('Lease')));
    await settle(tester);
    expect(find.byType(AppBottomSheet), findsNothing);
    expect(find.byType(ExtractedTextPage), findsOneWidget);
    await close(tester);
  });

  testWidgets('Settings', (tester) async {
    final router = await pumpApp(tester);
    router.go(Routes.settings);
    await settle(tester);
    expectNothingCutOff(tester, 'Settings');
    await close(tester);
  });

  for (final mode in [ScanMode.document, ScanMode.idCard]) {
    testWidgets('Viewer bar and Share sheet (${mode.name})', (tester) async {
      final d = mode == ScanMode.document ? doc : card;
      final router = await pumpApp(tester);
      router.go(Routes.viewer(d.id));
      await settle(tester);
      expectNothingCutOff(tester, 'Viewer');

      await tester.tap(find.widgetWithText(PrimaryButton, l.viewerShare).first);
      await settle(tester);
      expect(find.byType(AppBottomSheet), findsOneWidget);
      expect(find.textContaining(l.sharePreparingPages(0, 0).split(' ').first), findsOneWidget, reason: 'builds on open');
      expectNothingCutOff(tester, 'Share sheet');
      await close(tester);
    });
  }

  testWidgets('Print', (tester) async {
    final router = await pumpApp(tester);
    router.go(Routes.print(card.id));
    await settle(tester);
    expectNothingCutOff(tester, 'Print');
    await close(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('Adjust edges and Enhance (${dark ? 'dark' : 'light'} app theme)', (tester) async {
      final router = await pumpApp(tester, mode: dark ? ThemeMode.dark : ThemeMode.light);
      final args = EditorArgs(pages: doc.sortedPages, mode: doc.mode, documentId: doc.id);
      router.go(Routes.adjust, extra: args);
      await settle(tester);
      expect(find.text(l.adjustRotateLeft), findsOneWidget);
      expectNothingCutOff(tester, 'Adjust edges');

      router.go(Routes.enhance, extra: getIt<PageEditorBloc>(param1: args)..add(EditorStarted(args)));
      await settle(tester);
      expect(find.text(l.enhanceAdjust), findsOneWidget);
      expectNothingCutOff(tester, 'Enhance');

      await tester.tap(find.text(l.enhanceAdjust));
      await settle(tester);
      expect(find.text(l.enhanceBrightness), findsOneWidget);
      expectNothingCutOff(tester, 'Enhance, Adjust open');
      await close(tester);
    });
  }

  for (final mode in [ScanMode.document, ScanMode.idCard]) {
    testWidgets('Camera overlay (${mode.name})', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CameraOverlay(
            preview: const ColoredBox(color: Colors.black),
            rules: ScanModeRules.of(mode),
            title: mode == ScanMode.document ? l.modeDocument : '${l.modeIdCard} · ${l.cameraGuideFront}',
            guide: mode == ScanMode.document ? l.cameraHintDocument : l.cameraHintCard,
            flashOn: false,
            captureCount: 2,
            canFinish: true,
            showModes: true,
            capturing: false,
            onClose: () {},
            onFlash: () {},
            onMode: (_) {},
            onShutter: () {},
            onFinish: () {},
            onGallery: () {},
            banner: Text(l.cameraCardBlurry),
          ),
        ),
      );
      await settle(tester);
      expectNothingCutOff(tester, 'Camera');
    });
  }
}
