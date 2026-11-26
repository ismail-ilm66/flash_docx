import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/id.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/scanner/data/draft_service.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_checks.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
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
/// preview, sharpness / brightness checks). "Done" hands the photos not
/// ready yet to Adjust edges, which they join when they are (round 11b,
/// P0-18); the queue keeps going after the camera closes.
@injectable
class ScanSessionBloc extends Bloc<ScanSessionEvent, ScanSessionState> {
  ScanSessionBloc(
    this._prepare,
    this._prefs,
    this._previews,
    this._drafts,
    @factoryParam ScanMode? initialMode,
    @factoryParam bool? keepDraft,
  )   : _keepDraft = keepDraft ?? false,
        super(
          ScanSessionState(
            mode: initialMode ?? ScanMode.document,
            // Round 7, P0-1: Document always starts with the flash off (it
            // adds a metering delay and glare on paper); cards remember it.
            flashOn: (initialMode ?? ScanMode.document) != ScanMode.document && _prefs.flashOn,
          ),
        ) {
    on<SessionModeChanged>(_onMode);
    on<SessionFlashToggled>(_onFlash);
    on<SessionCaptured>(_onCaptured);
    on<_CaptureProcessed>(_onProcessed);
    on<_CaptureThumbReady>((e, emit) {
      final i = state.captures.indexWhere((c) => c.id == e.id);
      if (i < 0) return;
      final list = [...state.captures];
      list[i] = list[i].copyWith(thumb: e.path);
      // copyWith clears the result unless it's passed on.
      emit(state.copyWith(captures: list, result: state.result));
    });
    on<SessionCaptureRemoved>(_onRemoved);
    on<SessionRetakeRequested>(_onRetake);
    on<SessionNoticeDismissed>((_, emit) => emit(state.copyWith(clearNotice: true)));
    on<SessionImported>(_onImported);
    on<SessionFinished>(_onFinished);
    on<SessionReset>((_, emit) {
      _discardAll(state.captures);
      if (_keepDraft) unawaited(_drafts.discard());
      emit(ScanSessionState(mode: state.mode, flashOn: state.flashOn));
    });
  }

  /// Round 7, P0-3: a new scan (not a retake, an added page or a tool scan)
  /// is saved as a draft as each page is ready.
  final bool _keepDraft;
  final DraftService _drafts;

  @override
  void onChange(Change<ScanSessionState> change) {
    super.onChange(change);
    if (!_keepDraft || change.nextState.status == SessionStatus.ready) return;
    final before = change.currentState.captures;
    final after = change.nextState.captures;
    if (identical(before, after)) return;
    List<ScanPage> pages(List<Capture> cs) => [for (final c in cs) ?c.page];
    final next = pages(after);
    if (listEquals(pages(before), next)) return;
    unawaited(_drafts.save(change.nextState.mode, next));
  }

  final PreparePages _prepare;
  final PrefsService _prefs;
  final PreviewCache _previews;

  /// Serial background queue: one page at a time.
  Future<void> _queue = Future.value();

  /// Each capture's prepared page (null if it couldn't be read), by
  /// capture id.
  final Map<String, Future<({ScanPage page, bool blurry})?>> _jobs = {};

  /// Round 7, P0-4: a document page partly smeared or clearly unreadable.
  bool _blurry(AutoEditsResult? r) =>
      state.rules.aspectRatio == null && ((r?.blurry ?? false) || CaptureChecks.isBlurry(r?.sharpness));

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
    final capture = Capture(newId(), e.path, side: state.nextSide, guide: e.guide, capture: e.capture);
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
    final done = Completer<({ScanPage page, bool blurry})?>();
    _jobs[c.id] = done.future;
    _queue = _queue.then((_) async {
      // Skip captures that were removed while waiting (also after the
      // camera closed: discarding a scan clears them).
      if (!state.captures.any((x) => x.id == c.id)) return done.complete();
      final sw = Stopwatch()..start();
      AutoEditsResult? res;
      final r = await _prepare(
        [c.path],
        mode: mode,
        sides: [c.side],
        fallbacks: [c.guide],
        captures: [c.capture],
        copySource: false,
        onPrepared: (_, result) => res = result,
      );
      debugPrint('[capture] processed in background in ${sw.elapsedMilliseconds} ms');
      done.complete(r.fold((_) => null, (pages) => (page: pages.single, blurry: _blurry(res))));
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
      // Round 7, P0-4: blur is never raised here, on the camera, nor for
      // ID / passport. A document page that's partly smeared (2 of 9
      // cells) or clearly unreadable gets a short banner on Adjust edges.
      list[i] = list[i].copyWith(
        status: CaptureStatus.ready,
        page: e.page,
        sharpness: e.result?.sharpness,
        brightness: e.result?.brightness,
        blurry: _blurry(e.result),
      );
      // The stack shows the cropped page, not the photo (P0-3).
      final page = e.page!;
      unawaited(
        _previews.quick(page).then((q) {
          if (!isClosed) add(_CaptureThumbReady(e.id, q));
        }).catchError((Object err) {
          debugPrint('[capture] stack thumb: $err');
        }),
      );
      if (!state.flashOn && CaptureChecks.isDark(e.result?.brightness)) {
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

  /// Imports skip the camera (same pipeline). Round 11b, P0-19: Adjust
  /// edges opens at once and each picture joins it as it's ready.
  void _onImported(SessionImported e, Emitter<ScanSessionState> emit) {
    if (e.paths.isEmpty) return;
    final jobs = _prepare.oneByOne(e.paths, mode: state.mode);
    emit(
      state.copyWith(
        status: SessionStatus.ready,
        result: const [],
        pending: [
          for (final (i, j) in jobs.indexed) (order: i, page: j.then((p) => p == null ? null : (page: p, blurry: false))),
        ],
      ),
    );
  }

  void _onFinished(SessionFinished e, Emitter<ScanSessionState> emit) {
    if (!state.canFinish) return;
    if (e.waitAll) {
      emit(state.copyWith(waitingForQueue: true, status: SessionStatus.preparing));
      _maybeFinish(emit);
      return;
    }
    // Round 11b, P0-18: Adjust edges opens now; photos still in the queue
    // join it as they're ready. The order is the place in the scan.
    final pages = <ScanPage>[];
    final pending = <PendingPage>[];
    for (final (i, c) in state.captures.indexed) {
      if (c.page != null) {
        pages.add(c.page!.copyWith(order: i));
      } else if (c.status == CaptureStatus.processing) {
        pending.add((order: i, page: _jobs[c.id] ?? Future.value()));
      }
    }
    if (pages.isEmpty && pending.isEmpty) {
      emit(state.copyWith(status: SessionStatus.failed, failure: const ImageProcessingFailure('no readable photos')));
      return;
    }
    emit(state.copyWith(status: SessionStatus.ready, result: pages, pending: pending));
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
