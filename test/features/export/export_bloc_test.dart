import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
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
    mode: ScanMode.single,
    pages: const [ScanPage(id: 'p', documentId: 'd', originalPath: '/x', edits: PageEdits(), order: 0)],
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
  });

  test('defaults come from prefs and the document title', () {
    final bloc = ExportBloc(export, prefs, doc);
    expect(bloc.state.options.format, ExportFormat.jpg);
    expect(bloc.state.options.fileName, 'Doc');
    expect(bloc.state.requiredUnlock, isNull);
  });

  test('premium options require an unlock until granted', () {
    final bloc = ExportBloc(export, prefs, doc);
    bloc.add(ExportOptionsChanged(bloc.state.options.copyWith(quality: ExportQuality.high)));
    expect(bloc.stream, emitsThrough(predicate<ExportState>((s) => s.requiredUnlock == PremiumFeature.highQualityExport)));
  });

  test('unlocked feature clears the requirement', () async {
    final bloc = ExportBloc(export, prefs, doc);
    bloc
      ..add(ExportOptionsChanged(bloc.state.options.copyWith(format: ExportFormat.png)))
      ..add(const ExportFeatureUnlocked(PremiumFeature.pngExport));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.requiredUnlock, isNull);
  });

  test('export reports progress then done', () async {
    when(() => export(any(), any(), any(), onProgress: any(named: 'onProgress'))).thenAnswer((inv) async {
      final cb = inv.namedArguments[#onProgress] as void Function(double)?;
      cb?.call(0.5);
      cb?.call(1);
      return const Right(unit);
    });
    final bloc = ExportBloc(export, prefs, doc)..add(const ExportRequested(ExportTarget.share));
    await expectLater(
      bloc.stream,
      emitsInOrder([
        predicate<ExportState>((s) => s.status == const ExportWorking(0)),
        predicate<ExportState>((s) => s.status == const ExportWorking(0.5)),
        predicate<ExportState>((s) => s.status == const ExportWorking(1)),
        predicate<ExportState>((s) => s.status == const ExportDone(ExportTarget.share)),
      ]),
    );
  });

  test('cancelled share goes back to idle, other failures surface', () async {
    when(() => export(any(), any(), any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async => const Left(CancelledFailure()));
    var bloc = ExportBloc(export, prefs, doc)..add(const ExportRequested(ExportTarget.share));
    await expectLater(bloc.stream, emitsThrough(predicate<ExportState>((s) => s.status is ExportIdle)));

    when(() => export(any(), any(), any(), onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async => const Left(PdfFailure('x')));
    bloc = ExportBloc(export, prefs, doc)..add(const ExportRequested(ExportTarget.saveToPhone));
    await expectLater(bloc.stream, emitsThrough(predicate<ExportState>((s) => s.status is ExportFailed)));
  });
}
