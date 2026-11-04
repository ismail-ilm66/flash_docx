import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

// ---------- events ----------
sealed class ExportEvent {
  const ExportEvent();
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

// ---------- state ----------
sealed class ExportStatus extends Equatable {
  const ExportStatus();
  @override
  List<Object?> get props => [];
}

class ExportIdle extends ExportStatus {
  const ExportIdle();
}

class ExportWorking extends ExportStatus {
  const ExportWorking(this.progress);
  final double progress;
  @override
  List<Object?> get props => [progress];
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
    this.unlocked = const {},
  });

  final ScanDocument document;
  final ExportOptions options;
  final ExportStatus status;

  /// Features unlocked by a video for this export session.
  final Set<PremiumFeature> unlocked;

  /// Premium feature required by the current options, if not yet unlocked.
  PremiumFeature? get requiredUnlock {
    if (options.quality == ExportQuality.high && !unlocked.contains(PremiumFeature.highQualityExport)) {
      return PremiumFeature.highQualityExport;
    }
    if (options.format == ExportFormat.png && !unlocked.contains(PremiumFeature.pngExport)) {
      return PremiumFeature.pngExport;
    }
    return null;
  }

  ExportState copyWith({ExportOptions? options, ExportStatus? status, Set<PremiumFeature>? unlocked}) =>
      ExportState(
        document: document,
        options: options ?? this.options,
        status: status ?? this.status,
        unlocked: unlocked ?? this.unlocked,
      );

  @override
  List<Object?> get props => [document, options, status, unlocked];
}

@injectable
class ExportBloc extends Bloc<ExportEvent, ExportState> {
  ExportBloc(this._export, PrefsService prefs, @factoryParam ScanDocument document)
      : super(ExportState(document: document, options: _defaults(prefs, document))) {
    on<ExportOptionsChanged>((e, emit) => emit(state.copyWith(options: e.options, status: const ExportIdle())));
    on<ExportFeatureUnlocked>((e, emit) => emit(state.copyWith(unlocked: {...state.unlocked, e.feature})));
    on<ExportRequested>(_onExport);
  }

  final ExportDocument _export;

  static ExportOptions _defaults(PrefsService p, ScanDocument doc) => ExportOptions(
        format: ExportFormat.values.where((f) => f.name == p.defaultExportFormat).firstOrNull ?? ExportFormat.pdf,
        pageSize: PdfPageSize.values.where((s) => s.name == p.defaultPageSize).firstOrNull ?? PdfPageSize.a4,
        fileName: doc.title,
      );

  Future<void> _onExport(ExportRequested e, Emitter<ExportState> emit) async {
    if (state.status is ExportWorking) return;
    emit(state.copyWith(status: const ExportWorking(0)));
    final r = await _export(
      state.document,
      state.options,
      e.target,
      onProgress: (p) {
        if (!isClosed) emit(state.copyWith(status: ExportWorking(p)));
      },
    );
    emit(
      r.fold(
        (f) => state.copyWith(status: f is CancelledFailure ? const ExportIdle() : ExportFailed(f)),
        (_) => state.copyWith(status: ExportDone(e.target)),
      ),
    );
  }
}
