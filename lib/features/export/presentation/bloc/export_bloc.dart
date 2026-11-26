import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/step_timer.dart';
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

/// Round 11, P0-13: share only these pages (ids); all when every page.
class ExportPagesChanged extends ExportEvent {
  const ExportPagesChanged(this.pageIds);
  final Set<String> pageIds;
}

/// What a prepared export was made for: the options (without the file
/// name) and the pages.
typedef _JobKey = (ExportOptions, String);

class _PrepStep extends ExportEvent {
  const _PrepStep(this.key, this.done, this.total);
  final _JobKey key;
  final int done;
  final int total;
}

class _PrepFinished extends ExportEvent {
  const _PrepFinished(this.key, this.result);
  final _JobKey key;
  final Either<Failure, PreparedExport> result;
}

// ---------- state ----------

/// Progress of building the files for the current options.
class ExportPrep extends Equatable {
  const ExportPrep(
    this.done,
    this.total, {
    this.ready = false,
    this.bytes,
    this.hardToRead = false,
    this.failure,
  });
  final int done;
  final int total;
  final bool ready;

  /// Max file size: the final size, and whether small text may be hard to
  /// read at the settings it took.
  final int? bytes;
  final bool hardToRead;

  /// Building failed (for Max file size: it couldn't fit).
  final Failure? failure;

  @override
  List<Object?> get props => [done, total, ready, bytes, hardToRead, failure];
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
    ScanDocument? all,
    this.status = const ExportIdle(),
    this.unlocked = unlockedByDefault,
    this.prep,
  }) : all = all ?? document;

  /// The pages being shared ([all]'s, or the ones picked, round 11 P0-13).
  final ScanDocument document;

  /// The whole document.
  final ScanDocument all;
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

  /// Not every page is being shared.
  bool get somePages => document.pages.length != all.pages.length;

  ExportState copyWith({
    ScanDocument? document,
    ExportOptions? options,
    ExportStatus? status,
    Set<PremiumFeature>? unlocked,
    ExportPrep? prep,
  }) => ExportState(
    document: document ?? this.document,
    all: all,
    options: options ?? this.options,
    status: status ?? this.status,
    unlocked: unlocked ?? this.unlocked,
    prep: prep ?? this.prep,
  );

  @override
  List<Object?> get props => [document, all, options, status, unlocked, prep];
}

@injectable
class ExportBloc extends Bloc<ExportEvent, ExportState> {
  ExportBloc(
    this._export,
    this._prefs,
    @factoryParam ScanDocument document,
  ) : super(
        ExportState(document: document, options: defaultsFor(_prefs, document)),
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
      e.result.fold(
        (f) {
          if (f is! CancelledFailure) {
            emit(state.copyWith(prep: ExportPrep(total, total, failure: f)));
          }
        },
        (p) => emit(
          state.copyWith(
            prep: ExportPrep(
              total,
              total,
              ready: true,
              bytes: p.shrunk == null ? null : p.bytes,
              hardToRead: p.shrunk?.hardToRead ?? false,
            ),
          ),
        ),
      );
    });
    on<ExportRequested>(_onExport);
    on<ExportPagesChanged>((e, emit) {
      final keep = [for (final p in state.all.sortedPages) if (e.pageIds.contains(p.id)) p];
      if (keep.isEmpty) return;
      final doc = keep.length == state.all.pages.length ? state.all : state.all.copyWith(pages: keep);
      emit(
        state.copyWith(
          document: doc,
          options: state.options.copyWith(fileName: withPagesSuffix(state.options.fileName, state.all, keep)),
          status: const ExportIdle(),
        ),
      );
      if (_jobKey != null) _startPrep(emit);
    });
  }

  /// "Flash Scan – 24 Nov 2026 (p. 3, 7)" when only some pages are shared
  /// (runs: "p. 2–5, 8"); [name] without the suffix when all are.
  static String withPagesSuffix(String name, ScanDocument all, List<ScanPage> shared) {
    final base = name.replaceFirst(RegExp(r' \(p\. [0-9–, ]+\)$'), '');
    if (shared.length == all.pages.length) return base;
    final order = [for (final p in all.sortedPages) p.id];
    final nums = [for (final p in shared) order.indexOf(p.id) + 1]..sort();
    final parts = <String>[];
    for (var i = 0; i < nums.length; i++) {
      var j = i;
      while (j + 1 < nums.length && nums[j + 1] == nums[j] + 1) {
        j++;
      }
      parts.add(j - i >= 2 ? '${nums[i]}–${nums[j]}' : [for (var k = i; k <= j; k++) nums[k]].join(', '));
      i = j;
    }
    return '$base (p. ${parts.join(', ')})';
  }

  final ExportDocument _export;
  final PrefsService _prefs;

  Future<Either<Failure, PreparedExport>>? _job;
  _JobKey? _jobKey;
  CancelToken? _cancel;

  /// Round 10, P1-2: the format and layout last shared for this kind of
  /// scan; else ID cards as one image (front + back), documents in the
  /// Settings format.
  static ExportOptions defaultsFor(PrefsService p, ScanDocument doc) {
    final mode = doc.mode.name;
    T? named<T extends Enum>(List<T> values, String? name) => values.where((v) => v.name == name).firstOrNull;
    final remembered = named(ExportFormat.values, p.lastShareFormat(mode));
    final format = doc.mode == ScanMode.photo
        // A passport photo is shared as a picture, never a PDF.
        ? (remembered == ExportFormat.png || (remembered == null && p.defaultExportFormat == ExportFormat.png.name)
              ? ExportFormat.png
              : ExportFormat.jpg)
        : remembered ??
              (doc.mode == ScanMode.idCard
                  ? ExportFormat.jpg
                  : named(ExportFormat.values, p.defaultExportFormat) ?? ExportFormat.pdf);
    return ExportOptions(
        format: format,
        layout: named(ExportLayout.values, p.lastShareLayout(mode)) ?? ExportLayout.oneImage,
        pageSize:
            PdfPageSize.values
                .where((s) => s.name == p.defaultPageSize)
                .firstOrNull ??
            PdfPageSize.auto,
        quality:
            ExportQuality.values
                .where((q) => q.name == p.defaultQuality)
                .firstOrNull ??
            ExportQuality.standard,
        fileName: doc.title,
        footer: p.exportFooter,
      );
  }

  /// What the prepared files depend on: everything but the file name.
  static ExportOptions _keyOf(ExportOptions o) => o.copyWith(fileName: '');

  /// Starts building the files for the current options; an older job stops
  /// before its next page.
  Future<Either<Failure, PreparedExport>> _startPrep(
    Emitter<ExportState> emit,
  ) {
    final key = _keyOf(state.options);
    final jobKey = (key, [for (final p in state.document.pages) p.id].join(','));
    if (jobKey == _jobKey && _job != null) return _job!;
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    final sw = Stopwatch()..start();
    _jobKey = jobKey;
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
        if (!isClosed) add(_PrepStep(jobKey, done, total));
      },
    );
    job.then((r) {
      if (r.isRight()) {
        debugPrint(
          '[perf] share ready in ${sw.elapsedMilliseconds} ms '
          '(${state.document.pages.length} pages, ${key.format.name} ${key.quality.name})',
        );
      }
      if (!isClosed) add(_PrepFinished(jobKey, r));
    });
    return job;
  }

  Future<void> _onExport(ExportRequested e, Emitter<ExportState> emit) async {
    if (state.status is ExportWorking) return;
    final options = state.options;
    unawaited(_prefs.setLastShare(state.document.mode.name, format: options.format.name, layout: options.layout.name));
    final timer = StepTimer('share tap → sheet (${e.target.name})');
    emit(state.copyWith(status: ExportWorking(e.target)));
    // Uses the file built since the sheet opened, or waits for it.
    var r = await _startPrep(emit);
    // A previous job that failed (not just superseded) gets one fresh try;
    // a file that can't fit the size limit won't fit on a second try either.
    final failed = r.getLeft().toNullable();
    if (failed != null &&
        failed is! CancelledFailure &&
        failed is! ShrinkFailure) {
      _job = null;
      r = await _startPrep(emit);
    }
    timer.lap('wait for prepared file');
    final out = await r.fold(
      (f) async => Left<Failure, Unit>(f),
      (prepared) => _export.deliver(
        state.document,
        prepared.files,
        options,
        e.target,
        timer: timer,
      ),
    );
    // deliver removed the prepared files: a second Share prepares again
    // (from the cached page renders, so it's quick).
    _job = null;
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
