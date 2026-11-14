import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
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
    this.quick = const {},
    this.quickVersions = const {},
  });

  final ScanDocument? document;
  final int index;
  final bool loading;
  final Failure? failure;
  final bool deleted;

  /// Placeholders while a page's processed preview is made (P0-4): the
  /// editor's preview of that look, else the crop-only render.
  final Map<String, String> quick;

  /// The [versionOf] each [quick] entry was made for. After an edit the old
  /// one (an older crop or filter) is never shown.
  final Map<String, int> quickVersions;

  /// What page [p] shows: processed preview, else the placeholder made for
  /// its current edits, else null (spinner). Never the original photo.
  String? imageFor(ScanPage p) {
    final processed = p.processedPath;
    if (processed != null && File(processed).existsSync()) return processed;
    return quickVersions[p.id] == versionOf(p) ? quick[p.id] : null;
  }

  static int versionOf(ScanPage p) => Object.hash(p.originalPath, p.edits);

  List<ScanPage> get pages => document?.sortedPages ?? const [];
  ScanPage? get current => pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];

  ViewerState copyWith({
    ScanDocument? document,
    int? index,
    bool? loading,
    Failure? failure,
    bool? deleted,
    Map<String, String>? quick,
    Map<String, int>? quickVersions,
  }) =>
      ViewerState(
        document: document ?? this.document,
        index: index ?? this.index,
        loading: loading ?? this.loading,
        failure: failure,
        deleted: deleted ?? this.deleted,
        quick: quick ?? this.quick,
        quickVersions: quickVersions ?? this.quickVersions,
      );

  @override
  List<Object?> get props => [document, index, loading, failure, deleted, quick, quickVersions];
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
    this._previews,
    this._suggestions,
    this._setFolder,
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
  final PreviewCache _previews;
  final NameSuggestionActions _suggestions;
  final SetDocumentFolder _setFolder;
  StreamSubscription<ScanDocument?>? _sub;

  void _onDoc(ScanDocument? doc) {
    if (doc == null) {
      emit(state.copyWith(loading: false, deleted: state.document != null));
      return;
    }
    // Placeholders already on disk (the editor's previews right after Done)
    // go in with the document, so an edited page never shows its old crop.
    final quick = {...state.quick};
    final versions = {...state.quickVersions};
    for (final p in doc.pages) {
      if (state.imageFor(p) != null) continue;
      final ready = _previews.lookIfReady(p) ?? _previews.quickIfReady(p);
      if (ready == null) continue;
      quick[p.id] = ready;
      versions[p.id] = ViewerState.versionOf(p);
    }
    emit(state.copyWith(
      document: doc,
      loading: false,
      index: state.index.clamp(0, doc.pages.isEmpty ? 0 : doc.pages.length - 1),
      quick: quick,
      quickVersions: versions,
    ));
    unawaited(_placeholders(doc));
    unawaited(_render.ensureCaches(doc).catchError((Object e) => debugPrint('cache: $e')));
  }

  void select(int i) => emit(state.copyWith(index: i));

  Future<Failure?> rename(String title) async =>
      (await _rename(state.document!.id, title)).fold((f) => f, (_) => null);

  /// The smart-name banner (feature 3).
  Future<Failure?> applySuggestion() async =>
      (await _suggestions.apply(state.document!)).fold((f) => f, (_) => null);

  Future<Failure?> dismissSuggestion() async =>
      (await _suggestions.dismiss(state.document!)).fold((f) => f, (_) => null);

  Future<Failure?> moveTo(DocFolder folder) async =>
      (await _setFolder(state.document!.id, folder)).fold((f) => f, (_) => null);

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

  /// Quick crop-only previews for pages whose processed preview isn't
  /// ready, current page first (interactive lane).
  Future<void> _placeholders(ScanDocument doc) async {
    final sw = Stopwatch()..start();
    final order = [...doc.sortedPages]..sort((a, b) => (a.id == state.current?.id ? 0 : 1).compareTo(b.id == state.current?.id ? 0 : 1));
    for (final p in order) {
      if (isClosed) return;
      if (state.imageFor(p) != null) continue;
      try {
        final path = await _previews.quick(p);
        if (isClosed) return;
        emit(state.copyWith(
          quick: {...state.quick, p.id: path},
          quickVersions: {...state.quickVersions, p.id: ViewerState.versionOf(p)},
        ));
        if (p.id == state.current?.id) debugPrint('[perf] viewer first image in ${sw.elapsedMilliseconds} ms');
      } catch (e) {
        debugPrint('quick preview failed: $e');
      }
    }
  }
}
