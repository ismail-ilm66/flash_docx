import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flash_dox/features/print_layout/domain/usecases/build_print_layout.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

sealed class PrintStatus extends Equatable {
  const PrintStatus();
  @override
  List<Object?> get props => [];
}

class PrintIdle extends PrintStatus {
  const PrintIdle();
}

class PrintWorking extends PrintStatus {
  const PrintWorking();
}

class PrintDone extends PrintStatus {
  const PrintDone(this.target);
  final ExportTarget target;
  @override
  List<Object?> get props => [target];
}

class PrintFailed extends PrintStatus {
  const PrintFailed(this.failure);
  final Failure failure;
  @override
  List<Object?> get props => [failure];
}

class PrintLayoutState extends Equatable {
  const PrintLayoutState({
    this.document,
    this.output = PrintOutput.pdfDoubleSided,
    this.copies = 1,
    this.status = const PrintIdle(),
    this.moreCopiesUnlocked = false,
    this.failure,
    this.cutGuides = true,
    this.swapSides = false,
    this.sheet = 0,
  });

  final ScanDocument? document;
  final PrintOutput output;
  final int copies;
  final PrintStatus status;
  final bool moreCopiesUnlocked;
  final Failure? failure;
  final bool cutGuides;
  final bool swapSides;

  /// Which sheet the preview shows (double-sided PDFs have two).
  final int sheet;

  PrintKind? get kind => switch (document?.mode) {
        ScanMode.idCard => PrintKind.idCard,
        ScanMode.passport => PrintKind.passport,
        _ => null,
      };

  List<int> get allowedCopies =>
      kind == null ? const [1] : PrintLayoutCalculator.allowedCopies(kind!, output);

  List<PrintOutput> get allowedOutputs => document?.mode == ScanMode.passport
      ? const [PrintOutput.image, PrintOutput.pdfDoubleSided]
      : PrintOutput.values;

  bool copiesGated(int n) => n > 2 && !moreCopiesUnlocked;

  PrintLayoutState copyWith({
    ScanDocument? document,
    PrintOutput? output,
    int? copies,
    PrintStatus? status,
    bool? moreCopiesUnlocked,
    Failure? failure,
    bool? cutGuides,
    bool? swapSides,
    int? sheet,
  }) =>
      PrintLayoutState(
        document: document ?? this.document,
        output: output ?? this.output,
        copies: copies ?? this.copies,
        status: status ?? this.status,
        moreCopiesUnlocked: moreCopiesUnlocked ?? this.moreCopiesUnlocked,
        failure: failure,
        cutGuides: cutGuides ?? this.cutGuides,
        swapSides: swapSides ?? this.swapSides,
        sheet: sheet ?? this.sheet,
      );

  @override
  List<Object?> get props =>
      [document, output, copies, status, moreCopiesUnlocked, failure, cutGuides, swapSides, sheet];

  bool get hasBack => kind == PrintKind.idCard && (document?.pages.length ?? 0) > 1;
}

@injectable
class PrintLayoutCubit extends Cubit<PrintLayoutState> {
  PrintLayoutCubit(this._getDoc, this._build, @factoryParam String documentId)
      : super(const PrintLayoutState()) {
    unawaited(_load(documentId));
  }

  final GetDocument _getDoc;
  final BuildPrintLayout _build;

  Future<void> _load(String id) async {
    final r = await _getDoc(id);
    r.fold(
      (f) => emit(state.copyWith(failure: f)),
      (doc) => emit(
        state.copyWith(
          document: doc,
          output: doc.mode == ScanMode.passport ? PrintOutput.image : PrintOutput.pdfDoubleSided,
        ),
      ),
    );
  }

  void setOutput(PrintOutput o) {
    final allowed = state.kind == null ? const [1] : PrintLayoutCalculator.allowedCopies(state.kind!, o);
    emit(state.copyWith(output: o, copies: allowed.contains(state.copies) ? state.copies : allowed.first, status: const PrintIdle(), sheet: 0));
  }

  void setCopies(int n) => emit(state.copyWith(copies: n, status: const PrintIdle()));

  void setCutGuides(bool on) => emit(state.copyWith(cutGuides: on));

  void toggleSwapSides() => emit(state.copyWith(swapSides: !state.swapSides));

  void setSheet(int i) => emit(state.copyWith(sheet: i));

  void unlockMoreCopies() => emit(state.copyWith(moreCopiesUnlocked: true));

  Future<void> run(ExportTarget target) async {
    final doc = state.document;
    final kind = state.kind;
    if (doc == null || kind == null || state.status is PrintWorking) return;
    emit(state.copyWith(status: const PrintWorking()));
    final r = await _build(
      doc,
      kind: kind,
      output: state.output,
      copies: state.copies,
      target: target,
      cutGuides: state.cutGuides,
      swapSides: state.swapSides,
    );
    emit(
      r.fold(
        (f) => state.copyWith(status: f is CancelledFailure ? const PrintIdle() : PrintFailed(f)),
        (_) => state.copyWith(status: PrintDone(target)),
      ),
    );
  }
}
