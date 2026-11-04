import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flash_dox/features/scanner/presentation/bloc/scan_session_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPrepare extends Mock implements PreparePages {}

void main() {
  late _MockPrepare prepare;
  late PrefsService prefs;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PrefsService(await SharedPreferences.getInstance());
    prepare = _MockPrepare();
    tmp = await Directory.systemTemp.createTemp('session');
    registerFallbackValue(ScanMode.single);
  });

  tearDown(() => tmp.delete(recursive: true));

  String shot(String n) {
    final f = File('${tmp.path}/$n.jpg')..writeAsBytesSync([0]);
    return f.path;
  }

  ScanPage page(String id) => ScanPage(id: id, documentId: '', originalPath: '/x', edits: const PageEdits(), order: 0);

  test('single mode finishes after one capture and hands over draft pages', () async {
    when(() => prepare(any(), mode: any(named: 'mode'), sides: any(named: 'sides'), copySource: any(named: 'copySource')))
        .thenAnswer((_) async => Right([page('a')]));
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.single);
    bloc.add(SessionCaptured(shot('1')));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.isComplete, isTrue);
    expect(bloc.state.canCapture, isFalse);
    bloc.add(const SessionFinished());
    await expectLater(
      bloc.stream,
      emitsThrough(predicate<ScanSessionState>((s) => s.status == SessionStatus.ready && s.result!.length == 1)),
    );
    await bloc.close();
  });

  test('id card assigns front then back', () async {
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.idCard);
    expect(bloc.state.nextSide, CardSide.front);
    bloc.add(SessionCaptured(shot('f')));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.nextSide, CardSide.back);
    bloc.add(SessionCaptured(shot('b')));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.captures.map((c) => c.side), [CardSide.front, CardSide.back]);
    expect(bloc.state.isComplete, isTrue);
    await bloc.close();
  });

  test('removing a capture deletes the file; changing mode clears captures', () async {
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.batch);
    final p1 = shot('1');
    final p2 = shot('2');
    bloc
      ..add(SessionCaptured(p1))
      ..add(SessionCaptured(p2))
      ..add(const SessionCaptureRemoved(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bloc.state.count, 1);
    expect(File(p2).existsSync(), isFalse);
    bloc.add(const SessionModeChanged(ScanMode.single));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bloc.state.count, 0);
    expect(bloc.state.mode, ScanMode.single);
    await bloc.close();
  });

  test('import of several images switches single to batch; failure surfaces', () async {
    when(() => prepare(any(), mode: ScanMode.batch, sides: any(named: 'sides'), copySource: any(named: 'copySource')))
        .thenAnswer((_) async => const Left(ImageProcessingFailure('x')));
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.single);
    bloc.add(const SessionImported(['/a', '/b']));
    await expectLater(
      bloc.stream,
      emitsThrough(predicate<ScanSessionState>((s) => s.status == SessionStatus.failed && s.failure is ImageProcessingFailure)),
    );
    await bloc.close();
  });

  test('flash toggle persists', () async {
    final bloc = ScanSessionBloc(prepare, prefs, null);
    expect(bloc.state.flashOn, isFalse);
    bloc.add(const SessionFlashToggled());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(prefs.flashOn, isTrue);
    await bloc.close();
  });
}
