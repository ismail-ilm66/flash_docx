import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/export/presentation/bloc/export_bloc.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockExport extends Mock implements ExportDocument {}

void main() {
  late _MockExport export;
  late PrefsService prefs;
  final doc = ScanDocument(
    id: 'd',
    title: 'Doc',
    mode: ScanMode.document,
    pages: const [
      ScanPage(
        id: 'p',
        documentId: 'd',
        originalPath: '/x',
        edits: PageEdits(),
        order: 0,
      ),
    ],
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({'default_export_format': 'jpg'});
    prefs = PrefsService(await SharedPreferences.getInstance());
    export = _MockExport();
    registerFallbackValue(doc);
    registerFallbackValue(const ExportOptions());
    registerFallbackValue(ExportTarget.share);
    registerFallbackValue(<File>[]);
  });

  test('defaults come from prefs and the document title', () {
    final bloc = ExportBloc(export, prefs, doc);
    expect(bloc.state.options.format, ExportFormat.jpg);
    expect(bloc.state.options.fileName, 'Doc');
    expect(bloc.state.requiredUnlock, isNull);
  });

  test('round 10, P1-2: ID cards default to images, one picture; each mode remembers its last share', () async {
    SharedPreferences.setMockInitialValues({});
    final fresh = PrefsService(await SharedPreferences.getInstance());
    final card = doc.copyWith(mode: ScanMode.idCard);
    final first = ExportBloc(export, fresh, card);
    expect(first.state.options.format, ExportFormat.jpg);
    expect(first.state.options.layout, ExportLayout.oneImage);
    expect(ExportBloc(export, fresh, doc).state.options.format, ExportFormat.pdf);

    await fresh.setLastShare(ScanMode.idCard.name, format: 'pdf', layout: 'separate');
    final again = ExportBloc(export, fresh, card);
    expect((again.state.options.format, again.state.options.layout), (ExportFormat.pdf, ExportLayout.separate));
    expect(ExportBloc(export, fresh, doc).state.options.format, ExportFormat.pdf, reason: 'documents keep their own');
  });

  test(
    'premium options are free while rewarded ads are off',
    () async {
      final bloc = ExportBloc(export, prefs, doc);
      bloc.add(
        ExportOptionsChanged(
          bloc.state.options.copyWith(
            quality: ExportQuality.high,
            format: ExportFormat.png,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.requiredUnlock, isNull);
    },
    skip: rewardedAdsEnabled,
  );

  test(
    'premium options require an unlock until granted',
    skip: !rewardedAdsEnabled,
    () {
      final bloc = ExportBloc(export, prefs, doc);
      bloc.add(
        ExportOptionsChanged(
          bloc.state.options.copyWith(quality: ExportQuality.high),
        ),
      );
      expect(
        bloc.stream,
        emitsThrough(
          predicate<ExportState>(
            (s) => s.requiredUnlock == PremiumFeature.highQualityExport,
          ),
        ),
      );
    },
  );

  test(
    'unlocked feature clears the requirement',
    skip: !rewardedAdsEnabled,
    () async {
      final bloc = ExportBloc(export, prefs, doc);
      bloc
        ..add(
          ExportOptionsChanged(
            bloc.state.options.copyWith(format: ExportFormat.png),
          ),
        )
        ..add(const ExportFeatureUnlocked(PremiumFeature.pngExport));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.requiredUnlock, isNull);
    },
  );

  void stubPrepare({Either<Failure, PreparedExport> result = const Right(PreparedExport([]))}) {
    when(
      () => export.prepare(
        any(),
        any(),
        onStep: any(named: 'onStep'),
        cancel: any(named: 'cancel'),
      ),
    ).thenAnswer((inv) async {
      final step = inv.namedArguments[#onStep] as void Function(int, int)?;
      step?.call(0, 1);
      step?.call(1, 1);
      return result;
    });
  }

  test(
    'P0-4: opening the sheet builds the default export; Share uses it',
    () async {
      stubPrepare();
      when(
        () => export.deliver(any(), any(), any(), any(), timer: any(named: 'timer')),
      ).thenAnswer((_) async => const Right(unit));
      final bloc = ExportBloc(export, prefs, doc)
        ..add(const ExportSheetOpened());
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<ExportState>((s) => s.prep?.ready ?? false)),
      );

      bloc.add(const ExportRequested(ExportTarget.share));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<ExportState>(
            (s) => s.status == const ExportDone(ExportTarget.share),
          ),
        ),
      );
      verify(
        () => export.prepare(
          any(),
          any(),
          onStep: any(named: 'onStep'),
          cancel: any(named: 'cancel'),
        ),
      ).called(1);
      verify(
        () => export.deliver(any(), any(), any(), ExportTarget.share, timer: any(named: 'timer')),
      ).called(1);
    },
  );

  test(
    'a new page size re-prepares; a new file name does not, and is used on share',
    () async {
      stubPrepare();
      when(
        () => export.deliver(any(), any(), any(), any(), timer: any(named: 'timer')),
      ).thenAnswer((_) async => const Right(unit));
      final bloc = ExportBloc(export, prefs, doc)
        ..add(const ExportSheetOpened());
      await Future<void>.delayed(Duration.zero);
      bloc
        ..add(
          ExportOptionsChanged(
            bloc.state.options.copyWith(fileName: 'Renamed'),
          ),
        )
        ..add(
          ExportOptionsChanged(
            bloc.state.options.copyWith(
              fileName: 'Renamed',
              pageSize: PdfPageSize.letter,
            ),
          ),
        )
        ..add(const ExportRequested(ExportTarget.share));
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<ExportState>((s) => s.status is ExportDone)),
      );
      final prepared = verify(
        () => export.prepare(
          any(),
          captureAny(),
          onStep: any(named: 'onStep'),
          cancel: any(named: 'cancel'),
        ),
      ).captured;
      expect(prepared.map((o) => (o as ExportOptions).pageSize), [
        PdfPageSize.auto, // round 8, P0-8: the new default
        PdfPageSize.letter,
      ]);
      final delivered =
          verify(
                () => export.deliver(any(), any(), captureAny(), any(), timer: any(named: 'timer')),
              ).captured.single
              as ExportOptions;
      expect(delivered.fileName, 'Renamed');
      expect(delivered.pageSize, PdfPageSize.letter);
    },
  );

  test('cancelled share goes back to idle, other failures surface', () async {
    stubPrepare();
    when(
      () => export.deliver(any(), any(), any(), any(), timer: any(named: 'timer')),
    ).thenAnswer((_) async => const Left(CancelledFailure()));
    var bloc = ExportBloc(export, prefs, doc)
      ..add(const ExportRequested(ExportTarget.share));
    await expectLater(
      bloc.stream,
      emitsThrough(predicate<ExportState>((s) => s.status is ExportIdle)),
    );

    stubPrepare(result: const Left(PdfFailure('x')));
    bloc = ExportBloc(export, prefs, doc)
      ..add(const ExportRequested(ExportTarget.saveToPhone));
    await expectLater(
      bloc.stream,
      emitsThrough(predicate<ExportState>((s) => s.status is ExportFailed)),
    );
  });

  test('Max file size: a limit that cannot fit in colour shows the offer; black and white re-prepares', () async {
    const fail = ShrinkFailure(targetBytes: 200000, smallestBytes: 260000, canTryGrayscale: true);
    when(() => export.prepare(any(), any(), onStep: any(named: 'onStep'), cancel: any(named: 'cancel'))).thenAnswer((inv) async {
      final o = inv.positionalArguments[1] as ExportOptions;
      return o.grayscaleToFit
          ? const Right(PreparedExport([], shrunk: ShrinkStep(1228, 60, grayscale: true)))
          : const Left(fail);
    });
    final bloc = ExportBloc(export, prefs, doc);
    bloc
      ..add(ExportOptionsChanged(bloc.state.options.copyWith(format: ExportFormat.pdf, maxBytes: 200000)))
      ..add(const ExportSheetOpened());
    await expectLater(bloc.stream, emitsThrough(predicate<ExportState>((s) => s.prep?.failure == fail)));

    bloc.add(ExportOptionsChanged(bloc.state.options.copyWith(grayscaleToFit: true)));
    await expectLater(bloc.stream, emitsThrough(predicate<ExportState>((s) => (s.prep?.ready ?? false) && s.prep!.hardToRead)));
  });

  test('round 11, P0-13: only some pages: those are prepared, the name says which', () async {
    final ten = doc.copyWith(
      title: 'Flash Scan – 24 Nov 2026',
      pages: [
        for (var i = 0; i < 10; i++) ScanPage(id: 'p$i', documentId: 'd', originalPath: '/$i', edits: const PageEdits(), order: i),
      ],
    );
    final prepared = <List<String>>[];
    when(() => export.prepare(any(), any(), cancel: any(named: 'cancel'), onStep: any(named: 'onStep'))).thenAnswer((inv) async {
      prepared.add([for (final p in (inv.positionalArguments[0] as ScanDocument).pages) p.id]);
      return const Left(CancelledFailure());
    });
    final bloc = ExportBloc(export, prefs, ten)
      ..add(const ExportSheetOpened())
      ..add(const ExportPagesChanged({'p2', 'p6'}));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.somePages, isTrue);
    expect(bloc.state.document.pages.map((p) => p.id), ['p2', 'p6']);
    expect(bloc.state.options.fileName, 'Flash Scan – 24 Nov 2026 (p. 3, 7)');
    expect(prepared.last, ['p2', 'p6'], reason: 'the files are made again for those pages');

    bloc.add(ExportPagesChanged({for (final p in ten.pages) p.id}));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.somePages, isFalse);
    expect(bloc.state.options.fileName, 'Flash Scan – 24 Nov 2026');
    await bloc.close();
  });

  test('page suffix: runs of 3+ pages are shortened', () {
    final ten = doc.copyWith(
      pages: [for (var i = 0; i < 10; i++) ScanPage(id: 'p$i', documentId: 'd', originalPath: '/$i', edits: const PageEdits(), order: i)],
    );
    List<ScanPage> pick(List<int> n) => [for (final i in n) ten.pages[i]];
    expect(ExportBloc.withPagesSuffix('Doc', ten, pick([1, 2, 3, 4, 7])), 'Doc (p. 2–5, 8)');
    expect(ExportBloc.withPagesSuffix('Doc (p. 2–5, 8)', ten, pick([0, 1])), 'Doc (p. 1, 2)');
  });
}
