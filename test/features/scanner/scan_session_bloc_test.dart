import 'dart:async';
import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_checks.dart';
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

  /// Each queued job waits on its own completer so tests control timing.
  final gates = <String, Completer<void>>{};
  final sharpnessFor = <String, double>{};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PrefsService(await SharedPreferences.getInstance());
    prepare = _MockPrepare();
    tmp = await Directory.systemTemp.createTemp('session');
    gates.clear();
    sharpnessFor.clear();
    registerFallbackValue(ScanMode.document);
    when(
      () => prepare(
        any(),
        mode: any(named: 'mode'),
        sides: any(named: 'sides'),
        fallbacks: any(named: 'fallbacks'),
        copySource: any(named: 'copySource'),
        onPrepared: any(named: 'onPrepared'),
      ),
    ).thenAnswer((inv) async {
      final path = (inv.positionalArguments.first as List<String>).single;
      await (gates[path] ??= Completer<void>()..complete()).future;
      final side = (inv.namedArguments[#sides] as List<CardSide?>?)?.single;
      final page = ScanPage(id: path, documentId: '', originalPath: path, edits: const PageEdits(), order: 0, side: side);
      final cb = inv.namedArguments[#onPrepared] as void Function(int, AutoEditsResult)?;
      cb?.call(0, AutoEditsResult(edits: const PageEdits(), detected: true, sharpness: sharpnessFor[path] ?? 500, brightness: 150));
      return Right([page]);
    });
  });

  tearDown(() => tmp.delete(recursive: true));

  String shot(String n, {bool hold = false}) {
    final f = File('${tmp.path}/$n.jpg')..writeAsBytesSync([0]);
    if (hold) gates[f.path] = Completer<void>();
    return f.path;
  }

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('the shutter only records; Done waits for the queue, then hands over pages in order', () async {
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.document);
    final a = shot('a', hold: true);
    final b = shot('b', hold: true);
    bloc
      ..add(SessionCaptured(a))
      ..add(SessionCaptured(b));
    await pump();
    expect(bloc.state.count, 2);
    expect(bloc.state.canCapture, isTrue, reason: 'camera stays ready while processing');
    expect(bloc.state.processed, 0);

    bloc.add(const SessionFinished());
    await pump();
    expect(bloc.state.status, SessionStatus.preparing);
    expect(bloc.state.waitingForQueue, isTrue);

    gates[a]!.complete();
    await pump();
    expect(bloc.state.processed, 1);
    expect(bloc.state.status, SessionStatus.preparing);

    gates[b]!.complete();
    await pump();
    expect(bloc.state.status, SessionStatus.ready);
    expect(bloc.state.result!.map((p) => p.id), [a, b]);
    await bloc.close();
  });

  test('a blurry photo raises a notice; Retake puts the next shot in its place', () async {
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.document);
    final a = shot('a');
    final b = shot('b');
    final c = shot('c');
    sharpnessFor[b] = CaptureChecks.blurThreshold - 1;
    bloc
      ..add(SessionCaptured(a))
      ..add(SessionCaptured(b))
      ..add(SessionCaptured(c));
    await pump();
    final notice = bloc.state.notice!;
    expect(notice.kind, NoticeKind.blurry);
    expect(bloc.state.captures[1].path, b);

    bloc.add(SessionRetakeRequested(notice.captureId));
    await pump();
    expect(bloc.state.count, 2);
    expect(bloc.state.notice, isNull);
    expect(File(b).existsSync(), isFalse);

    final b2 = shot('b2');
    bloc.add(SessionCaptured(b2));
    await pump();
    expect(bloc.state.captures.map((c) => c.path), [a, b2, c]);
    await bloc.close();
  });

  test('ID card keeps front / back when the back is retaken', () async {
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.idCard);
    final f = shot('front');
    final back = shot('back');
    sharpnessFor[back] = 1;
    bloc.add(SessionCaptured(f));
    await pump();
    expect(bloc.state.nextSide, CardSide.back);
    bloc.add(SessionCaptured(back));
    await pump();
    bloc.add(SessionRetakeRequested(bloc.state.notice!.captureId));
    await pump();
    expect(bloc.state.nextSide, CardSide.back);
    bloc.add(SessionCaptured(shot('back2')));
    await pump();
    expect(bloc.state.captures.map((c) => c.side), [CardSide.front, CardSide.back]);
    await bloc.close();
  });

  test('removing a capture while it waits in the queue skips it and deletes the file', () async {
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.document);
    final a = shot('a', hold: true);
    final b = shot('b');
    bloc
      ..add(SessionCaptured(a))
      ..add(SessionCaptured(b));
    await pump();
    bloc.add(const SessionCaptureRemoved(1));
    await pump();
    gates[a]!.complete();
    await pump();
    expect(bloc.state.captures.map((c) => c.path), [a]);
    expect(File(b).existsSync(), isFalse);
    verifyNever(
      () => prepare(
        [b],
        mode: any(named: 'mode'),
        sides: any(named: 'sides'),
        fallbacks: any(named: 'fallbacks'),
        copySource: any(named: 'copySource'),
        onPrepared: any(named: 'onPrepared'),
      ),
    );
    await bloc.close();
  });

  test('an unreadable photo is skipped at Done; all unreadable fails', () async {
    when(
      () => prepare(
        any(),
        mode: any(named: 'mode'),
        sides: any(named: 'sides'),
        fallbacks: any(named: 'fallbacks'),
        copySource: any(named: 'copySource'),
        onPrepared: any(named: 'onPrepared'),
      ),
    ).thenAnswer((_) async => const Left(ImageProcessingFailure('x')));
    final bloc = ScanSessionBloc(prepare, prefs, ScanMode.document);
    bloc.add(SessionCaptured(shot('a')));
    await pump();
    expect(bloc.state.notice?.kind, NoticeKind.unreadable);
    bloc.add(const SessionFinished());
    await pump();
    expect(bloc.state.status, SessionStatus.failed);
    await bloc.close();
  });

  test('a dark photo suggests the flash only while the flash is off', () async {
    when(
      () => prepare(
        any(),
        mode: any(named: 'mode'),
        sides: any(named: 'sides'),
        fallbacks: any(named: 'fallbacks'),
        copySource: any(named: 'copySource'),
        onPrepared: any(named: 'onPrepared'),
      ),
    ).thenAnswer((inv) async {
      final path = (inv.positionalArguments.first as List<String>).single;
      final cb = inv.namedArguments[#onPrepared] as void Function(int, AutoEditsResult)?;
      cb?.call(0, const AutoEditsResult(edits: PageEdits(), detected: true, sharpness: 500, brightness: CaptureChecks.darkThreshold - 1));
      return Right([ScanPage(id: path, documentId: '', originalPath: path, edits: const PageEdits(), order: 0)]);
    });
    final bloc = ScanSessionBloc(prepare, prefs, null);
    expect(bloc.state.mode, ScanMode.document, reason: 'camera always opens in Document');
    bloc.add(SessionCaptured(shot('dark1')));
    await pump();
    expect(bloc.state.notice?.kind, NoticeKind.dark);

    bloc
      ..add(const SessionNoticeDismissed())
      ..add(const SessionFlashToggled());
    await pump();
    expect(prefs.flashOn, isTrue, reason: 'flash choice persists');
    bloc.add(SessionCaptured(shot('dark2')));
    await pump();
    expect(bloc.state.notice, isNull);
    await bloc.close();
  });
}
