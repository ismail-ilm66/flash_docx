import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class ViewerState extends Equatable {
  const ViewerState({
    this.document,
    this.index = 0,
    this.loading = true,
    this.failure,
    this.deleted = false,
  });

  final ScanDocument? document;
  final int index;
  final bool loading;
  final Failure? failure;
  final bool deleted;

  List<ScanPage> get pages => document?.sortedPages ?? const [];
  ScanPage? get current => pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];

  ViewerState copyWith({
    ScanDocument? document,
    int? index,
    bool? loading,
    Failure? failure,
    bool? deleted,
  }) =>
      ViewerState(
        document: document ?? this.document,
        index: index ?? this.index,
        loading: loading ?? this.loading,
        failure: failure,
        deleted: deleted ?? this.deleted,
      );

  @override
  List<Object?> get props => [document, index, loading, failure, deleted];
}

@injectable
class ViewerCubit extends Cubit<ViewerState> {
  ViewerCubit(
    this._watch,
    this._rename,
    this._delete,
    this._deletePage,
    this._reorder,
    this._addPages,
    this._render,
    @factoryParam String documentId,
  ) : super(const ViewerState()) {
    _sub = _watch(documentId).listen(_onDoc, onError: (Object e) {
      emit(state.copyWith(loading: false, failure: DatabaseFailure(e.toString())));
    });
  }

  final WatchDocument _watch;
  final RenameDocument _rename;
  final DeleteDocument _delete;
  final DeletePage _deletePage;
  final ReorderPages _reorder;
  final AddPages _addPages;
  final PageRenderService _render;
  StreamSubscription<ScanDocument?>? _sub;

  void _onDoc(ScanDocument? doc) {
    if (doc == null) {
      emit(state.copyWith(loading: false, deleted: state.document != null));
      return;
    }
    emit(state.copyWith(document: doc, loading: false, index: state.index.clamp(0, doc.pages.isEmpty ? 0 : doc.pages.length - 1)));
    unawaited(_render.ensureCaches(doc).catchError((Object e) => debugPrint('cache: $e')));
  }

  void select(int i) => emit(state.copyWith(index: i));

  Future<Failure?> rename(String title) async =>
      (await _rename(state.document!.id, title)).fold((f) => f, (_) => null);

  Future<Failure?> delete() async =>
      (await _delete(state.document!.id)).fold((f) => f, (_) => null);

  Future<Failure?> deleteCurrentPage() async {
    final p = state.current;
    if (p == null) return null;
    return (await _deletePage(p.id)).fold((f) => f, (_) => null);
  }

  Future<Failure?> addPages(List<ScanPage> pages) async =>
      (await _addPages(state.document!.id, pages)).fold((f) => f, (_) => null);

  Future<Failure?> reorder(List<String> ids) async =>
      (await _reorder(state.document!.id, ids)).fold((f) => f, (_) => null);

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
