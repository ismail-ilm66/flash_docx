import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/ocr/domain/recognize_page_text.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

enum OcrScope { page, allPages }

sealed class OcrStatus extends Equatable {
  const OcrStatus();
  @override
  List<Object?> get props => [];
}

class OcrIdle extends OcrStatus {
  const OcrIdle();
}

class OcrWorking extends OcrStatus {
  const OcrWorking(this.done, this.total);
  final int done;
  final int total;
  @override
  List<Object?> get props => [done, total];
}

class OcrDone extends OcrStatus {
  const OcrDone();
}

class OcrFailed extends OcrStatus {
  const OcrFailed(this.failure);
  final Failure failure;
  @override
  List<Object?> get props => [failure];
}

class OcrState extends Equatable {
  const OcrState({
    this.document,
    this.pageId,
    this.scope = OcrScope.page,
    this.status = const OcrIdle(),
    this.text = '',
    this.allPagesUnlocked = false,
  });

  final ScanDocument? document;
  final String? pageId;
  final OcrScope scope;
  final OcrStatus status;
  final String text;
  final bool allPagesUnlocked;

  ScanPage? get page =>
      document?.pages.where((p) => p.id == pageId).firstOrNull ?? document?.cover;

  OcrState copyWith({
    ScanDocument? document,
    String? pageId,
    OcrScope? scope,
    OcrStatus? status,
    String? text,
    bool? allPagesUnlocked,
  }) =>
      OcrState(
        document: document ?? this.document,
        pageId: pageId ?? this.pageId,
        scope: scope ?? this.scope,
        status: status ?? this.status,
        text: text ?? this.text,
        allPagesUnlocked: allPagesUnlocked ?? this.allPagesUnlocked,
      );

  @override
  List<Object?> get props => [document, pageId, scope, status, text, allPagesUnlocked];
}

@injectable
class OcrCubit extends Cubit<OcrState> {
  OcrCubit(
    this._getDoc,
    this._recognize,
    this._log,
    @factoryParam String documentId,
    @factoryParam String? pageId,
  ) : super(OcrState(pageId: pageId)) {
    unawaited(_load(documentId));
  }

  final GetDocument _getDoc;
  final RecognizePageText _recognize;
  final LogActivity _log;

  /// Separator pattern; the localised string is supplied by the UI.
  String Function(int n) separator = (n) => '--- Page $n ---';

  Future<void> _load(String id) async {
    final r = await _getDoc(id);
    r.fold(
      (f) => emit(state.copyWith(status: OcrFailed(f))),
      (doc) {
        emit(state.copyWith(document: doc));
        unawaited(run());
      },
    );
  }

  void setScope(OcrScope s) {
    if (s == state.scope) return;
    emit(state.copyWith(scope: s));
    unawaited(run());
  }

  void selectPage(String id) {
    emit(state.copyWith(pageId: id, scope: OcrScope.page));
    unawaited(run());
  }

  void unlockAllPages() => emit(state.copyWith(allPagesUnlocked: true));

  void setText(String t) => emit(state.copyWith(text: t));

  Future<void> run() async {
    final doc = state.document;
    if (doc == null) return;
    final pages = state.scope == OcrScope.page
        ? [if (state.page != null) state.page!]
        : doc.sortedPages;
    if (pages.isEmpty) return;
    emit(state.copyWith(status: OcrWorking(0, pages.length), text: ''));
    final buf = StringBuffer();
    for (final (i, p) in pages.indexed) {
      final r = await _recognize(p);
      if (isClosed) return;
      final failed = r.fold((f) => f, (_) => null);
      if (failed != null) {
        emit(state.copyWith(status: OcrFailed(failed)));
        return;
      }
      final text = r.getOrElse((_) => '');
      if (pages.length > 1) {
        if (i > 0) buf.writeln();
        buf.writeln(separator(i + 1));
      }
      buf.writeln(text);
      emit(state.copyWith(status: OcrWorking(i + 1, pages.length), text: buf.toString().trimRight()));
    }
    emit(state.copyWith(status: const OcrDone(), text: buf.toString().trimRight()));
  }

  Future<void> logCopied() async {
    final id = state.document?.id;
    if (id != null) await _log(id, ActivityType.textCopied);
  }
}
