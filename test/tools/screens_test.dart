@Tags(['screens'])
library;

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
import 'package:flash_dox/features/settings/presentation/cubit/theme_cubit.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screenshots of real screens with the real image pipeline, for checking
/// a layout against its artboard. Not part of the normal run:
///   flutter test test/tools/screens_test.dart --tags screens --run-skipped --update-goldens
/// writes build/screens/*.png.
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

Future<void> _loadFonts() async {
  final loader = FontLoader(AppTheme.fontFamily);
  for (final w in [400, 500, 600, 700, 800]) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Manrope-$w.ttf').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  late Directory tmp;
  late ScanDocument card;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await _loadFonts();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('screens');
    PathProviderPlatform.instance = _Paths(tmp);
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    await configureDependencies();
    getIt
      ..unregister<AppDatabase>()
      ..registerLazySingleton<AppDatabase>(() => AppDatabase.test(NativeDatabase.memory()));
    final files = getIt<FileStore>();
    ScanPage page(String src, String id, int order, CardSide side) {
      final path = files.newCapturePath(id);
      File(src).copySync(path);
      return ScanPage(
        id: id,
        documentId: '',
        originalPath: path,
        edits: const PageEdits(filter: FilterType.idColor, outputAspect: 85.6 / 54),
        order: order,
        side: side,
      );
    }

    card = (await getIt<CreateDocument>()(
      mode: ScanMode.idCard,
      pages: [
        page('store/sample_docs/idfront.jpg', 'f', 0, CardSide.front),
        page('store/sample_docs/idback.jpg', 'k', 1, CardSide.back),
      ],
      title: 'CNIC – front & back',
    ))
        .getOrElse((f) => throw StateError('$f'));
  });

  tearDown(() async {
    await getIt.reset(dispose: false);
    await tmp.delete(recursive: true);
  });

  Future<GoRouter> pumpApp(WidgetTester tester, String location) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.swtnoa.flashdox/share_in/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    final router = buildRouter(initialLocation: location);
    await tester.pumpWidget(
      BlocProvider.value(
        value: getIt<ThemeCubit>(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    return router;
  }

  Future<void> real(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final images = find.byType(Image).evaluate().map((e) => (e.widget as Image).image);
      for (final img in images) {
        await precacheImage(img, find.byType(Image).evaluate().first);
      }
    });
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../build/screens/$name.png'));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('print layout', (tester) async {
    await pumpApp(tester, Routes.print(card.id));
    await real(tester);
    await shot(tester, 'print');
    await close(tester);
  }, skip: !File('store/sample_docs/idfront.jpg').existsSync());

  testWidgets('passport photo sheet and single photo', (tester) async {
    final path = getIt<FileStore>().newCapturePath('face');
    File('store/sample_docs/idfront.jpg').copySync(path);
    final photo = (await tester.runAsync(
      () => getIt<CreateDocument>()(
        mode: ScanMode.photo,
        pages: [ScanPage(id: 'ph', documentId: '', originalPath: path, edits: const PageEdits(photoWidthMm: 35, photoHeightMm: 45), order: 0)],
        title: 'Passport photo',
      ),
    ))!
        .getOrElse((f) => throw StateError('$f'));
    await pumpApp(tester, Routes.photoSheet(photo.id));
    await real(tester);
    await shot(tester, 'photo_sheet');
    await tester.tap(find.text('Single photo'));
    await real(tester);
    await shot(tester, 'photo_single');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await real(tester, rounds: 5);
    await shot(tester, 'photo_single_options');
    await close(tester);
  }, skip: !File('store/sample_docs/idfront.jpg').existsSync());
}
