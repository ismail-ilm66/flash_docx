import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

// ---------- events ----------
sealed class ExportEvent {
  const ExportEvent();
}

/// The sheet opened: start building the default export (P0-4 point 6).
class ExportSheetOpened extends ExportEvent {
  const ExportSheetOpened();
}

class ExportOptionsChanged extends ExportEvent {
  const ExportOptionsChanged(this.options);
  final ExportOptions options;
}

class ExportRequested extends ExportEvent {
  const ExportRequested(this.target);
  final ExportTarget target;
}

class ExportFeatureUnlocked extends ExportEvent {
  const ExportFeatureUnlocked(this.feature);
  final PremiumFeature feature;
}

class _PrepStep extends ExportEvent {
  const _PrepStep(this.key, this.done, this.total);
  final ExportOptions key;
  final int done;
  final int total;
}

class _PrepFinished extends ExportEvent {
  const _PrepFinished(this.key, this.ok);
  final ExportOptions key;
  final bool ok;
}

// ---------- state ----------

/// Progress of building the files for the current options.
class ExportPrep extends Equatable {
  const ExportPrep(this.done, this.total, {this.ready = false});
  final int done;
  final int total;
  final bool ready;
  @override
  List<Object?> get props => [done, total, ready];
}

sealed class ExportStatus extends Equatable {
  const ExportStatus();
  @override
  List<Object?> get props => [];
}

class ExportIdle extends ExportStatus {
  const ExportIdle();
}

/// The user tapped Share / Save: waiting for the files, then the system
/// sheet.
class ExportWorking extends ExportStatus {
  const ExportWorking(this.target);
  final ExportTarget target;
  @override
  List<Object?> get props => [target];
}

class ExportDone extends ExportStatus {
  const ExportDone(this.target);
  final ExportTarget target;
  @override
  List<Object?> get props => [target];
}

class ExportFailed extends ExportStatus {
  const ExportFailed(this.failure);
  final Failure failure;
  @override
  List<Object?> get props => [failure];
}

class ExportState extends Equatable {
  const ExportState({
    required this.document,
    required this.options,
    this.status = const ExportIdle(),
    this.unlocked = unlockedByDefault,
    this.prep,
  });

  final ScanDocument document;
  final ExportOptions options;
  final ExportStatus status;

  /// null until the sheet starts preparing.
  final ExportPrep? prep;

  /// Features unlocked by a video for this export session.
  final Set<PremiumFeature> unlocked;

  /// Premium feature required by the current options, if not yet unlocked.
  PremiumFeature? get requiredUnlock {
    if (options.quality == ExportQuality.high &&
        !unlocked.contains(PremiumFeature.highQualityExport)) {
      return PremiumFeature.highQualityExport;
    }
    if (options.format == ExportFormat.png &&
        !unlocked.contains(PremiumFeature.pngExport)) {
      return PremiumFeature.pngExport;
    }
    return null;
  }

  ExportState copyWith({
    ExportOptions? options,
    ExportStatus? status,
    Set<PremiumFeature>? unlocked,
    ExportPrep? prep,
  }) => ExportState(
    document: document,
    options: options ?? this.options,
    status: status ?? this.status,
    unlocked: unlocked ?? this.unlocked,
    prep: prep ?? this.prep,
  );

  @override
  List<Object?> get props => [document, options, status, unlocked, prep];
}

@injectable
class ExportBloc extends Bloc<ExportEvent, ExportState> {
  ExportBloc(
    this._export,
    PrefsService prefs,
    @factoryParam ScanDocument document,
  ) : super(
        ExportState(document: document, options: _defaults(prefs, document)),
      ) {
    on<ExportSheetOpened>((e, emit) => _startPrep(emit));
    on<ExportOptionsChanged>((e, emit) {
      final changed = _keyOf(e.options) != _keyOf(state.options);
      emit(state.copyWith(options: e.options, status: const ExportIdle()));
      // The file name alone doesn't change the files; it's applied on share.
      if (changed && _jobKey != null) _startPrep(emit);
    });
    on<ExportFeatureUnlocked>(
      (e, emit) =>
          emit(state.copyWith(unlocked: {...state.unlocked, e.feature})),
    );
    on<_PrepStep>((e, emit) {
      if (e.key == _jobKey) {
        emit(state.copyWith(prep: ExportPrep(e.done, e.total)));
      }
    });
    on<_PrepFinished>((e, emit) {
      if (e.key != _jobKey) return;
      final total = state.prep?.total ?? 0;
      emit(state.copyWith(prep: ExportPrep(total, total, ready: e.ok)));
    });
    on<ExportRequested>(_onExport);
  }

  final ExportDocument _export;

  Future<Either<Failure, List<File>>>? _job;
  ExportOptions? _jobKey;
  CancelToken? _cancel;

  static ExportOptions _defaults(PrefsService p, ScanDocument doc) =>
      ExportOptions(
        format:
            ExportFormat.values
                .where((f) => f.name == p.defaultExportFormat)
                .firstOrNull ??
            ExportFormat.pdf,
        pageSize:
            PdfPageSize.values
                .where((s) => s.name == p.defaultPageSize)
                .firstOrNull ??
            PdfPageSize.a4,
        quality:
            ExportQuality.values
                .where((q) => q.name == p.defaultQuality)
                .firstOrNull ??
            ExportQuality.standard,
        fileName: doc.title,
      );

  /// What the prepared files depend on: everything but the file name.
  static ExportOptions _keyOf(ExportOptions o) => o.copyWith(fileName: '');

  /// Starts building the files for the current options; an older job stops
  /// before its next page.
  Future<Either<Failure, List<File>>> _startPrep(Emitter<ExportState> emit) {
    final key = _keyOf(state.options);
    if (key == _jobKey && _job != null) return _job!;
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    final sw = Stopwatch()..start();
    _jobKey = key;
    emit(
      state.copyWith(
        prep: ExportPrep(0, ExportDocument.stepsFor(state.document, key)),
      ),
    );
    final job = _job = _export.prepare(
      state.document,
      key,
      cancel: token,
      onStep: (done, total) {
        if (!isClosed) add(_PrepStep(key, done, total));
      },
    );
    job.then((r) {
      if (r.isRight()) {
        debugPrint(
          '[perf] share ready in ${sw.elapsedMilliseconds} ms '
          '(${state.document.pages.length} pages, ${key.format.name} ${key.quality.name})',
        );
      }
      if (!isClosed) add(_PrepFinished(key, r.isRight()));
    });
    return job;
  }

  Future<void> _onExport(ExportRequested e, Emitter<ExportState> emit) async {
    if (state.status is ExportWorking) return;
    final options = state.options;
    emit(state.copyWith(status: ExportWorking(e.target)));
    // Uses the file built since the sheet opened, or waits for it.
    var r = await _startPrep(emit);
    // A previous job that failed (not just superseded) gets one fresh try.
    if (r.isLeft() && r.getLeft().toNullable() is! CancelledFailure) {
      _job = null;
      r = await _startPrep(emit);
    }
    final out = await r.fold(
      (f) async => Left<Failure, Unit>(f),
      (files) => _export.deliver(state.document, files, options, e.target),
    );
    if (isClosed) return;
    emit(
      out.fold(
        (f) => state.copyWith(
          status: f is CancelledFailure ? const ExportIdle() : ExportFailed(f),
        ),
        (_) => state.copyWith(status: ExportDone(e.target)),
      ),
    );
  }
}
