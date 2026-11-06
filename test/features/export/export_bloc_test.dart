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
        () => export.deliver(any(), any(), any(), any()),
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
        () => export.deliver(any(), any(), any(), ExportTarget.share),
      ).called(1);
    },
  );

  test(
    'a new page size re-prepares; a new file name does not, and is used on share',
    () async {
      stubPrepare();
      when(
        () => export.deliver(any(), any(), any(), any()),
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
        PdfPageSize.a4,
        PdfPageSize.letter,
      ]);
      final delivered =
          verify(
                () => export.deliver(any(), any(), captureAny(), any()),
              ).captured.single
              as ExportOptions;
      expect(delivered.fileName, 'Renamed');
      expect(delivered.pageSize, PdfPageSize.letter);
    },
  );

  test('cancelled share goes back to idle, other failures surface', () async {
    stubPrepare();
    when(
      () => export.deliver(any(), any(), any(), any()),
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
}
