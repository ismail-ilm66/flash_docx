import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_checks.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

part 'scan_session_event.dart';
part 'scan_session_state.dart';

/// One camera session (round 3, P0-C).
///
/// The shutter path only records the photo; every capture is processed in a
/// background queue, one page at a time (move, upright, edge detection,
/// preview, sharpness / brightness checks). "Done" waits for the queue.
@injectable
class ScanSessionBloc extends Bloc<ScanSessionEvent, ScanSessionState> {
  ScanSessionBloc(
    this._prepare,
    this._prefs,
    @factoryParam ScanMode? initialMode,
  ) : super(
          ScanSessionState(
            mode: initialMode ?? ScanMode.document,
            flashOn: _prefs.flashOn,
          ),
        ) {
    on<SessionModeChanged>(_onMode);
    on<SessionFlashToggled>(_onFlash);
    on<SessionCaptured>(_onCaptured);
    on<_CaptureProcessed>(_onProcessed);
    on<SessionCaptureRemoved>(_onRemoved);
    on<SessionRetakeRequested>(_onRetake);
    on<SessionNoticeDismissed>((_, emit) => emit(state.copyWith(clearNotice: true)));
    on<SessionImported>(_onImported);
    on<SessionFinished>(_onFinished);
    on<SessionReset>((_, emit) {
      _discardAll(state.captures);
      emit(ScanSessionState(mode: state.mode, flashOn: state.flashOn));
    });
  }

  final PreparePages _prepare;
  final PrefsService _prefs;

  /// Serial background queue: one page at a time.
  Future<void> _queue = Future.value();

  void _onMode(SessionModeChanged e, Emitter<ScanSessionState> emit) {
    // Changing mode mid-session discards captures.
    _discardAll(state.captures);
    emit(state.copyWith(mode: e.mode, captures: const [], clearNotice: true, clearInsertAt: true));
  }

  Future<void> _onFlash(SessionFlashToggled e, Emitter<ScanSessionState> emit) async {
    final v = !state.flashOn;
    emit(state.copyWith(flashOn: v));
    await _prefs.setFlashOn(v);
  }

  void _onCaptured(SessionCaptured e, Emitter<ScanSessionState> emit) {
    if (!state.canCapture) return;
    final capture = Capture(newId(), e.path, side: state.nextSide, guide: e.guide);
    final list = [...state.captures];
    final at = state.insertAt;
    if (at != null && at <= list.length) {
      list.insert(at, capture);
    } else {
      list.add(capture);
    }
    emit(state.copyWith(captures: list, clearInsertAt: true));
    _enqueue(capture);
  }

  void _enqueue(Capture c) {
    final mode = state.mode;
    _queue = _queue.then((_) async {
      if (isClosed) return;
      // Skip captures that were removed while waiting.
      if (!state.captures.any((x) => x.id == c.id)) return;
      final sw = Stopwatch()..start();
      AutoEditsResult? res;
      final r = await _prepare(
        [c.path],
        mode: mode,
        sides: [c.side],
        fallbacks: [c.guide],
        copySource: false,
        onPrepared: (_, result) => res = result,
      );
      debugPrint('[capture] processed in background in ${sw.elapsedMilliseconds} ms');
      if (isClosed) return;
      r.fold(
        (f) => add(_CaptureProcessed(c.id, null, null, f)),
        (pages) => add(_CaptureProcessed(c.id, pages.single, res, null)),
      );
    });
  }

  void _onProcessed(_CaptureProcessed e, Emitter<ScanSessionState> emit) {
    final i = state.captures.indexWhere((c) => c.id == e.id);
    if (i < 0) {
      // Removed meanwhile: clean up what the job produced.
      if (e.page != null) File(e.page!.originalPath).delete().ignore();
      return;
    }
    final list = [...state.captures];
    CaptureNotice? notice;
    if (e.page == null) {
      list[i] = list[i].copyWith(status: CaptureStatus.failed);
      notice = CaptureNotice(NoticeKind.unreadable, e.id);
    } else {
      list[i] = list[i].copyWith(
        status: CaptureStatus.ready,
        page: e.page,
        sharpness: e.result?.sharpness,
        brightness: e.result?.brightness,
      );
      if (CaptureChecks.isBlurry(e.result?.sharpness)) {
        notice = CaptureNotice(NoticeKind.blurry, e.id);
      } else if (!state.flashOn && CaptureChecks.isDark(e.result?.brightness)) {
        notice = CaptureNotice(NoticeKind.dark, e.id);
      }
    }
    emit(state.copyWith(captures: list, notice: notice));
    if (state.waitingForQueue) _maybeFinish(emit);
  }

  void _onRemoved(SessionCaptureRemoved e, Emitter<ScanSessionState> emit) {
    if (e.index < 0 || e.index >= state.captures.length) return;
    final list = [...state.captures];
    final removed = list.removeAt(e.index);
    _discardAll([removed]);
    emit(state.copyWith(captures: list, clearNotice: state.notice?.captureId == removed.id));
  }

  void _onRetake(SessionRetakeRequested e, Emitter<ScanSessionState> emit) {
    final i = state.captures.indexWhere((c) => c.id == e.captureId);
    if (i < 0) return;
    final list = [...state.captures];
    _discardAll([list.removeAt(i)]);
    emit(state.copyWith(captures: list, insertAt: i, clearNotice: true));
  }

  Future<void> _onImported(SessionImported e, Emitter<ScanSessionState> emit) async {
    // Imports skip the camera: prepare straight away (same pipeline).
    emit(state.copyWith(status: SessionStatus.preparing));
    final r = await _prepare(e.paths, mode: state.mode);
    emit(
      r.fold(
        (f) => state.copyWith(status: SessionStatus.failed, failure: f),
        (pages) => state.copyWith(status: SessionStatus.ready, result: pages),
      ),
    );
  }

  void _onFinished(SessionFinished e, Emitter<ScanSessionState> emit) {
    if (!state.canFinish) return;
    emit(state.copyWith(waitingForQueue: true, status: SessionStatus.preparing));
    _maybeFinish(emit);
  }

  void _maybeFinish(Emitter<ScanSessionState> emit) {
    if (state.captures.any((c) => c.status == CaptureStatus.processing)) return;
    final pages = [
      for (final (i, c) in state.captures.where((c) => c.page != null).indexed) c.page!.copyWith(order: i),
    ];
    if (pages.isEmpty) {
      emit(
        state.copyWith(
          status: SessionStatus.failed,
          failure: const ImageProcessingFailure('no readable photos'),
          waitingForQueue: false,
        ),
      );
      return;
    }
    emit(state.copyWith(status: SessionStatus.ready, result: pages, waitingForQueue: false));
  }

  void _discardAll(List<Capture> captures) {
    for (final c in captures) {
      File(c.path).delete().ignore();
      final p = c.page;
      if (p != null) File(p.originalPath).delete().ignore();
    }
  }
}
