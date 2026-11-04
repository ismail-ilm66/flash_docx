import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Order of the Recent activity list.
enum HomeSort { latest, oldest, name }

class HomeState extends Equatable {
  const HomeState({
    this.documents = const [],
    this.loading = true,
    this.search = '',
    this.sort = HomeSort.latest,
    this.failure,
  });

  /// Documents in [sort] order.
  final List<ScanDocument> documents;
  final bool loading;
  final String search;
  final HomeSort sort;
  final Failure? failure;

  HomeState copyWith({
    List<ScanDocument>? documents,
    bool? loading,
    String? search,
    HomeSort? sort,
    Failure? failure,
  }) =>
      HomeState(
        documents: documents ?? this.documents,
        loading: loading ?? this.loading,
        search: search ?? this.search,
        sort: sort ?? this.sort,
        failure: failure,
      );

  @override
  List<Object?> get props => [documents, loading, search, sort, failure];
}

List<ScanDocument> sortDocuments(List<ScanDocument> docs, HomeSort sort) {
  final out = [...docs];
  switch (sort) {
    case HomeSort.latest:
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case HomeSort.oldest:
      out.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    case HomeSort.name:
      out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
  return out;
}

@injectable
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._watch, this._delete, this._rename) : super(const HomeState()) {
    _subscribe();
  }

  final WatchDocuments _watch;
  final DeleteDocument _delete;
  final RenameDocument _rename;
  StreamSubscription<List<ScanDocument>>? _sub;

  void _subscribe() {
    _sub?.cancel();
    _sub = _watch(search: state.search.isEmpty ? null : state.search).listen(
      (docs) => emit(state.copyWith(documents: sortDocuments(docs, state.sort), loading: false)),
      onError: (Object e) => emit(
        state.copyWith(loading: false, failure: DatabaseFailure(e.toString())),
      ),
    );
  }

  void search(String q) {
    emit(state.copyWith(search: q));
    _subscribe();
  }

  void setSort(HomeSort sort) {
    if (sort == state.sort) return;
    emit(state.copyWith(sort: sort, documents: sortDocuments(state.documents, sort)));
  }

  Future<Failure?> delete(String id) async =>
      (await _delete(id)).fold((f) => f, (_) => null);

  Future<Failure?> rename(String id, String title) async =>
      (await _rename(id, title)).fold((f) => f, (_) => null);

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
