import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

part 'scan_session_event.dart';
part 'scan_session_state.dart';

/// One camera session: mode, flash, the stack of raw captures, and the
/// hand-off to the editor as draft pages.
@injectable
class ScanSessionBloc extends Bloc<ScanSessionEvent, ScanSessionState> {
  ScanSessionBloc(
    this._prepare,
    this._prefs,
    @factoryParam ScanMode? initialMode,
  ) : super(
          ScanSessionState(
            mode: initialMode ?? _modeFromPrefs(_prefs),
            flashOn: _prefs.flashOn,
          ),
        ) {
    on<SessionModeChanged>(_onMode);
    on<SessionFlashToggled>(_onFlash);
    on<SessionCaptured>(_onCaptured);
    on<SessionCaptureRemoved>(_onRemoved);
    on<SessionImported>(_onImported);
    on<SessionFinished>(_onFinished);
    on<SessionReset>((_, emit) => emit(ScanSessionState(mode: state.mode, flashOn: state.flashOn)));
  }

  final PreparePages _prepare;
  final PrefsService _prefs;

  static ScanMode _modeFromPrefs(PrefsService p) =>
      ScanMode.values.where((m) => m.name == p.defaultScanMode).firstOrNull ??
      ScanMode.single;

  void _onMode(SessionModeChanged e, Emitter<ScanSessionState> emit) {
    if (state.captures.isNotEmpty) {
      // Changing mode mid-session discards captures.
      for (final c in state.captures) {
        File(c.path).delete().ignore();
      }
    }
    emit(state.copyWith(mode: e.mode, captures: const []));
  }

  Future<void> _onFlash(SessionFlashToggled e, Emitter<ScanSessionState> emit) async {
    final v = !state.flashOn;
    emit(state.copyWith(flashOn: v));
    await _prefs.setFlashOn(v);
  }

  void _onCaptured(SessionCaptured e, Emitter<ScanSessionState> emit) {
    if (state.isComplete) return;
    final capture = Capture(e.path, side: state.nextSide);
    emit(state.copyWith(captures: [...state.captures, capture]));
  }

  void _onRemoved(SessionCaptureRemoved e, Emitter<ScanSessionState> emit) {
    if (e.index < 0 || e.index >= state.captures.length) return;
    final list = [...state.captures];
    File(list.removeAt(e.index).path).delete().ignore();
    emit(state.copyWith(captures: list));
  }

  Future<void> _onImported(SessionImported e, Emitter<ScanSessionState> emit) async {
    // Imports skip the camera: prepare straight away.
    emit(state.copyWith(status: SessionStatus.preparing));
    final mode = e.paths.length > 1 && state.mode == ScanMode.single
        ? ScanMode.batch
        : state.mode;
    final r = await _prepare(e.paths, mode: mode);
    emit(
      r.fold(
        (f) => state.copyWith(status: SessionStatus.failed, failure: f),
        (pages) => state.copyWith(mode: mode, status: SessionStatus.ready, result: pages),
      ),
    );
  }

  Future<void> _onFinished(SessionFinished e, Emitter<ScanSessionState> emit) async {
    if (!state.canFinish) return;
    emit(state.copyWith(status: SessionStatus.preparing));
    final r = await _prepare(
      state.captures.map((c) => c.path).toList(),
      mode: state.mode,
      sides: state.captures.map((c) => c.side).toList(),
      copySource: false,
    );
    emit(
      r.fold(
        (f) => state.copyWith(status: SessionStatus.failed, failure: f),
        (pages) => state.copyWith(status: SessionStatus.ready, result: pages),
      ),
    );
  }
}
