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
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/features/documents/presentation/widgets/folder_chips.dart';
import 'package:flash_dox/features/documents/presentation/widgets/pick_document_sheet.dart';
import 'package:flash_dox/features/documents/presentation/widgets/suggestion_banner.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/ocr/presentation/pages/extracted_text_page.dart';
import 'package:flash_dox/features/photo/domain/background_segmenter.dart';
import 'package:flash_dox/features/photo/presentation/photo_crop_page.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_overlay.dart';
import 'package:flash_dox/features/settings/presentation/cubit/theme_cubit.dart';
import 'package:flash_dox/features/signature/data/signature_store.dart';
import 'package:flash_dox/features/signature/presentation/pages/sign_document_page.dart';
import 'package:flash_dox/features/signature/presentation/widgets/draw_pad.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flash_dox/shared/widgets/zoomable_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:opencv_dart/opencv.dart' as cv;
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

/// Answers what the passport photo screens ask; the rest stays pending.
class _PhotoProcessor extends _PendingProcessor {
  @override
  Future<({int width, int height})> imageSize(String imagePath) async => (width: 3000, height: 4000);

  @override
  Future<String> renderPhoto(
    String originalPath,
    PageEdits edits, {
    required double widthMm,
    required double heightMm,
    required int dpi,
    required String outputPath,
  }) async {
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(File('test/fixtures/edges/box_colors_photo.jpg').readAsBytesSync());
    return outputPath;
  }

  @override
  Future<String> previewWithBackground(String photoPath, String maskPath, PhotoBackground background, {required String outputPath}) async {
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(File('test/fixtures/edges/box_colors_photo.jpg').readAsBytesSync());
    return outputPath;
  }
}

/// Segmentation stand-ins: a real mask file, or "not on this phone".
class _FakeSegmenter implements BackgroundSegmenter {
  _FakeSegmenter({required this.available});
  final bool available;

  @override
  Future<String?> maskFor(String photoPath) async {
    if (!available) return null;
    final out = getIt<FileStore>().newCapturePath('mask').replaceAll('.jpg', '.png');
    File(out).writeAsBytesSync(File('test/fixtures/edges/box_colors_photo.jpg').readAsBytesSync());
    return out;
  }
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
    await getIt<DocumentRepository>().setSuggestion(
      doc.id,
      const NameSuggestion(title: 'Electricity bill – Oct 2026', folder: DocFolder.bills, kind: 'an electricity bill'),
    );
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
    // Only what's on screen: a label counts when every route around it is
    // its navigator's current page, or the top page under a sheet / dialog
    // (pageless routes here are all popups). Covered routes aren't painted.
    bool onScreen(BuildContext ctx) {
      BuildContext? at = ctx;
      while (at != null) {
        final route = ModalRoute.of(at);
        if (route == null) return true;
        final nav = route.navigator!;
        final pages = nav.widget.pages;
        if (!route.isCurrent && !(pages.isNotEmpty && identical(route.settings, pages.last))) return false;
        at = nav.context;
        if (ModalRoute.of(at) == route) return true;
      }
      return true;
    }

    final cut = {
      for (final e in tester.allElements)
        if (e.renderObject case final RenderParagraph r)
          if (!r.debugNeedsLayout && r.didExceedMaxLines && r.overflow == TextOverflow.ellipsis && onScreen(e))
            '${r.text.toPlainText()} (${r.constraints.maxWidth.round()} px)',
    };
    expect(cut, isEmpty, reason: '$screen: labels cut off at 2× font');
  }

  Future<GoRouter> pumpApp(WidgetTester tester, {ThemeMode mode = ThemeMode.light, String location = Routes.home}) async {
    await setUpView(tester);
    // "Share to Flash Dox" has no platform side in tests.
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.flashdox.app/share_in/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    // Not the splash: it clears the temp folders the tests set up.
    final router = buildRouter(initialLocation: location);
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

  /// File reads, image decoding and encoding are real async work: let each
  /// step of a chain finish, then rebuild.
  Future<void> real(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
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
    // P1-1: Docs · ID Card · Passport · Import: equal width, one line each.
    final tiles = find.byType(QuickActionTile);
    expect(tiles, findsNWidgets(4));
    final widths = {for (final e in tiles.evaluate()) tester.getSize(find.byWidget(e.widget)).width.round()};
    expect(widths, hasLength(1), reason: 'equal width');
    for (final label in [l.homeDocument, l.homeIdCard, l.modePassport, l.homeImport]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: tiles, matching: find.text(label)));
      final lineHeight = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
      expect(paragraph.size.height, lessThan(lineHeight * 1.5), reason: '$label on one line');
    }
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.textContaining(l.sidesCount(2)), 200, scrollable: list);
    await settle(tester);
    expect(find.byType(FolderChips), findsOneWidget);
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
    expect(find.text(l.pickTitleText), findsOneWidget);
    expect(find.text(l.pickScanNew), findsOneWidget);
    expect(find.text(l.pickFromPhotos), findsOneWidget);
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

  testWidgets('P1-4: the tool picker returns Scan new / From photos / a document', (tester) async {
    await pumpApp(tester);
    await settle(tester);
    final ctx = tester.element(find.byType(Scaffold).first);
    for (final (label, want) in [(l.pickScanNew, PickScanNew), (l.pickFromPhotos, PickFromPhotos), ('Lease', PickedDocument)]) {
      ToolPick? got;
      unawaited(showPickDocumentSheet(ctx, tool: ToolTarget.sign).then((r) => got = r));
      await settle(tester);
      expect(find.text(l.pickTitleSign), findsOneWidget);
      expectNothingCutOff(tester, 'Pick, sign');
      await tester.tap(find.descendant(of: find.byType(AppBottomSheet), matching: find.text(label)));
      await settle(tester);
      expect(got.runtimeType, want);
    }
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
      if (mode == ScanMode.document) expect(find.byType(SuggestionBanner), findsOneWidget);
      expectNothingCutOff(tester, 'Viewer');

      await tester.tap(find.widgetWithText(PrimaryButton, l.viewerShare).first);
      await settle(tester);
      expect(find.byType(AppBottomSheet), findsOneWidget);
      expect(find.textContaining(l.sharePreparingPages(0, 0).split(' ').first), findsOneWidget, reason: 'builds on open');
      expectNothingCutOff(tester, 'Share sheet');

      if (mode == ScanMode.document) {
        await tester.scrollUntilVisible(find.text(l.shareMaxSize), 200, scrollable: find.byType(Scrollable).last);
        await tester.tap(find.text(l.shareMaxSize));
        await settle(tester);
        expect(find.text(l.maxSizeBody), findsOneWidget);
        expectNothingCutOff(tester, 'Max file size');
      }
      await close(tester);
    });
  }

  testWidgets('Passport photo: no segmentation, no White / Light blue', (tester) async {
    getIt
      ..unregister<ImageProcessor>()
      ..registerLazySingleton<ImageProcessor>(_PhotoProcessor.new)
      ..unregister<BackgroundSegmenter>()
      ..registerLazySingleton<BackgroundSegmenter>(() => _FakeSegmenter(available: false));
    final photo = getIt<FileStore>().newCapturePath('face');
    await tester.runAsync(() => File('test/fixtures/edges/box_colors_photo.jpg').copy(photo));
    final router = await pumpApp(tester);
    unawaited(router.push(Routes.photoCrop, extra: PhotoCropArgs(photoPath: photo)));
    await real(tester);
    expect(find.text(l.photoTopOfHead), findsOneWidget);
    expect(find.text(l.photoBackgroundWhite), findsNothing);
    expect(find.text(l.photoBackgroundLightBlue), findsNothing);
    await close(tester);
  });

  testWidgets('Passport photo share: pictures only, with size limits', (tester) async {
    final files = getIt<FileStore>();
    final path = files.newCapturePath('face');
    await tester.runAsync(() => File('test/fixtures/edges/box_colors_photo.jpg').copy(path));
    final photo = (await tester.runAsync(
      () => getIt<CreateDocument>()(
        mode: ScanMode.photo,
        pages: [ScanPage(id: 'ph', documentId: '', originalPath: path, edits: const PageEdits(photoWidthMm: 35, photoHeightMm: 45), order: 0)],
        title: 'Passport photo',
      ),
    ))!
        .getOrElse((f) => throw StateError('$f'));
    final router = await pumpApp(tester);
    router.go(Routes.viewer(photo.id));
    await settle(tester);
    await tester.tap(find.widgetWithText(PrimaryButton, l.viewerShare).first);
    await settle(tester);
    final sheet = find.byType(AppBottomSheet);
    expect(find.descendant(of: sheet, matching: find.text(l.sharePdf)), findsNothing, reason: 'no PDF for a photo');
    expect(find.descendant(of: sheet, matching: find.text(l.shareJpg)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(l.sharePng)), findsOneWidget);
    expectNothingCutOff(tester, 'Photo share');
    await tester.scrollUntilVisible(find.text(l.shareImageSize), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(l.shareImageSize));
    await settle(tester);
    expect(find.text(l.imageSizePrint(413, 531)), findsOneWidget);
    expectNothingCutOff(tester, 'Photo image size');
    await tester.tap(find.text(l.imageSizePx(600, 771)));
    await settle(tester);
    expect(find.text(l.imageSizePx(600, 771)), findsWidgets, reason: 'shown on the row');
    await tester.scrollUntilVisible(find.text(l.shareMaxSize), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(l.shareMaxSize));
    await settle(tester);
    expect(find.text(l.maxSizeUnder('50 KB')), findsOneWidget);
    expect(find.text(l.maxSizeUnder('1 MB')), findsNothing);
    expectNothingCutOff(tester, 'Photo max size');
    await close(tester);
  });

  testWidgets('Print', (tester) async {
    final router = await pumpApp(tester);
    router.go(Routes.print(card.id));
    await settle(tester);
    expectNothingCutOff(tester, 'Print');
    // P1-6: each output in the same zoomable viewer; sheets in a pill.
    for (final output in [l.printOutputDoubleSided, l.printOutputOnePage, l.printOutputImage]) {
      await tester.tap(find.text(output));
      await settle(tester);
      expect(find.byType(ZoomablePages), findsOneWidget, reason: output);
      expectNothingCutOff(tester, 'Print, $output');
      if (output == l.printOutputDoubleSided) expect(find.text(l.printSheetBacks(2)), findsOneWidget);
    }
    expect(find.text(l.printImageCaption('93.6', '120')), findsOneWidget, reason: 'tight image, not A4');
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

  testWidgets('Sign a document: add, move, save (feature 4)', (tester) async {
    final page = doc.sortedPages.first;
    await tester.runAsync(() async {
      final files = getIt<FileStore>();
      // The page without overlays (normally rendered on open).
      await File('test/fixtures/edges/box_colors_photo.jpg').copy(files.signBasePath(page.id, page.originalPath, page.edits));
      final sig = cv.Mat.zeros(60, 200, cv.MatType.CV_8UC4);
      cv.rectangle(sig, cv.Rect(10, 25, 180, 10), cv.Scalar(0, 0, 0, 255), thickness: -1);
      final (_, png) = cv.imencode('.png', sig);
      sig.dispose();
      await getIt<SignatureStore>().save(png, ink: InkColor.blue);
    });
    await pumpApp(tester, location: Routes.sign(doc.id));
    await real(tester);
    expect(find.text(l.signAddSignature), findsOneWidget);
    expectNothingCutOff(tester, 'Sign document');

    await tester.tap(find.text(l.signAddSignature));
    await real(tester);
    expect(find.byType(OverlayBox), findsOneWidget);
    final before = tester.widget<OverlayBox>(find.byType(OverlayBox)).overlay;
    await tester.drag(find.byType(OverlayBox), const Offset(30, -60));
    await tester.pump();
    final after = tester.widget<OverlayBox>(find.byType(OverlayBox)).overlay;
    expect(after.left, greaterThan(before.left));
    expect(after.top, lessThan(before.top));

    await tester.tap(find.text(l.signAddDate));
    await real(tester);
    expect(find.byType(OverlayBox), findsNWidgets(2));
    expectNothingCutOff(tester, 'Sign document with overlays');

    await tester.tap(find.text(l.enhanceDone));
    await real(tester);
    final saved = (await tester.runAsync(() => getIt<DocumentRepository>().get(doc.id)))!.getOrElse((f) => throw StateError('$f'));
    final overlays = saved.sortedPages.first.edits.overlays;
    expect(overlays.map((o) => o.kind), [OverlayKind.signature, OverlayKind.date]);
    expect(overlays.first.left, closeTo(after.left, 1e-9));
    expect(saved.lastActivity?.type, ActivityType.signed);
    expect(File(overlays.first.imagePath).existsSync(), isTrue);
    await close(tester);
  });

  testWidgets('My signature: draw and save', (tester) async {
    final router = await pumpApp(tester);
    router.go(Routes.signature);
    await settle(tester);
    expectNothingCutOff(tester, 'My signature');
    await tester.tap(find.text(l.mySignatureDraw));
    await settle(tester);
    // P1-5: sign on the sideways full-screen canvas, then back.
    await tester.tap(find.text(l.mySignatureExpand));
    await settle(tester);
    expect(find.byType(RotatedBox), findsWidgets);
    expectNothingCutOff(tester, 'Expanded signature');
    final big = find.byType(DrawPad);
    await tester.dragFrom(tester.getCenter(big) - const Offset(0, 120), const Offset(10, 240));
    await tester.pump();
    await tester.tap(find.text(l.commonDone));
    await settle(tester);
    final pad = find.byType(DrawPad);
    expect(tester.widget<DrawPad>(pad).controller.isEmpty, isFalse, reason: 'brought back into the pad');
    await tester.dragFrom(tester.getCenter(pad) - const Offset(80, 0), const Offset(160, 20));
    await tester.pump();
    await tester.tap(find.text(l.mySignatureSave));
    await real(tester);
    expect(getIt<SignatureStore>().saved.value, isTrue);
    expect(File(getIt<SignatureStore>().path).lengthSync(), greaterThan(100));
    await close(tester);
  });

  testWidgets('Passport photo: crop, then the print sheet (feature 5)', (tester) async {
    getIt
      ..unregister<ImageProcessor>()
      ..registerLazySingleton<ImageProcessor>(_PhotoProcessor.new)
      ..unregister<BackgroundSegmenter>()
      ..registerLazySingleton<BackgroundSegmenter>(() => _FakeSegmenter(available: true));
    final photo = getIt<FileStore>().newCapturePath('face');
    await tester.runAsync(() => File('test/fixtures/edges/box_colors_photo.jpg').copy(photo));
    final router = await pumpApp(tester);
    unawaited(router.push(Routes.photoCrop, extra: PhotoCropArgs(photoPath: photo)));
    await real(tester);
    expect(find.text(l.photoTopOfHead), findsOneWidget);
    expectNothingCutOff(tester, 'Passport photo crop');
    // Background: Original · White · Light blue, previewed on the stage.
    expect(find.text(l.photoBackgroundLightBlue), findsOneWidget);
    await tester.ensureVisible(find.text(l.photoBackgroundWhite));
    await tester.tap(find.text(l.photoBackgroundWhite));
    await real(tester);
    final stage = tester.widgetList<Image>(find.byType(Image)).map((i) => i.image).whereType<ResizeImage>().map((r) => (r.imageProvider as FileImage).file.path);
    expect(stage.any((p) => p.contains('bg_white_')), isTrue, reason: 'the white preview is on the stage');
    // P1-3.5: both look and are enabled once the photo is placed.
    expect(tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, l.photoMakeSheet)).onPressed, isNotNull);
    expect(tester.widget<TopBarTextAction>(find.widgetWithText(TopBarTextAction, l.adjustNext)).onPressed, isNotNull);

    // Pan the photo; the frame stays covered.
    await tester.dragFrom(tester.getCenter(find.text(l.photoTopOfHead)) - const Offset(60, -40), const Offset(-40, -40));
    await tester.pump();
    await tester.tap(find.text(l.photoMakeSheet));
    await real(tester);
    expect(find.text(l.photoSheetTitle), findsOneWidget);
    expect(find.text(l.photoSheetCaption(l.photoPaperA4, 12)), findsOneWidget);
    expectNothingCutOff(tester, 'Print sheet');

    await tester.tap(find.text(l.photoPaper4x6));
    await tester.pump();
    expect(find.text(l.photoSheetCaption(l.photoPaper4x6, 6)), findsOneWidget, reason: '12 does not fit: Full (6)');
    expectNothingCutOff(tester, 'Print sheet, 4 × 6');

    final docs = (await tester.runAsync(() => getIt<DocumentRepository>().watchAll().first))!;
    final saved = docs.firstWhere((d) => d.mode == ScanMode.photo);
    expect(saved.pages.single.edits.photoBackground, PhotoBackground.white);
    final mask = saved.pages.single.edits.backgroundMaskPath!;
    expect(p.isWithin(getIt<FileStore>().docDir(saved.id).path, mask), isTrue, reason: 'the mask is kept with the document');
    expect(saved.folder, DocFolder.ids);
    final e = saved.pages.single.edits;
    expect((e.photoWidthMm, e.photoHeightMm), (35.0, 45.0));
    final crop = e.crop!;
    final px = ((crop.tr.x - crop.tl.x) * 3000) / ((crop.bl.y - crop.tl.y) * 4000);
    expect(px, closeTo(35 / 45, 1e-3), reason: 'the crop has the photo shape');
    await close(tester);
  });

  for (final hint in CameraHint.values) {
    // P1-7: every entry point's hint fits at 2×.
    final mode = hint == CameraHint.idCard || hint == CameraHint.passport ? ScanMode.idCard : ScanMode.document;
    testWidgets('Camera overlay (${hint.name})', (tester) async {
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
            guide: cameraHintText(l, hint),
            // P1-3.1: passport photo has the flip and the self-timer.
            onFlip: hint == CameraHint.passportPhoto ? () {} : null,
            onTimer: hint == CameraHint.passportPhoto ? () {} : null,
            timerOn: hint == CameraHint.passportPhoto,
            countdown: hint == CameraHint.passportPhoto ? 3 : null,
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
