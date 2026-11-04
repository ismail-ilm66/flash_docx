import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class HomeState extends Equatable {
  const HomeState({
    this.documents = const [],
    this.loading = true,
    this.search = '',
    this.failure,
  });

  final List<ScanDocument> documents;
  final bool loading;
  final String search;
  final Failure? failure;

  HomeState copyWith({
    List<ScanDocument>? documents,
    bool? loading,
    String? search,
    Failure? failure,
  }) =>
      HomeState(
        documents: documents ?? this.documents,
        loading: loading ?? this.loading,
        search: search ?? this.search,
        failure: failure,
      );

  @override
  List<Object?> get props => [documents, loading, search, failure];
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
      (docs) => emit(state.copyWith(documents: docs, loading: false)),
      onError: (Object e) => emit(
        state.copyWith(loading: false, failure: DatabaseFailure(e.toString())),
      ),
    );
  }

  void search(String q) {
    emit(state.copyWith(search: q));
    _subscribe();
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
