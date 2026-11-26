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

/// An image the viewer shows for a page; `blurred` for a stretched
/// thumbnail standing in for the display image.
typedef ViewerImage = ({String path, bool blurred});

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

  /// Stand-ins while a page's display image is made: Enhance's image of
  /// exactly that look (filtered, right after Done).
  final Map<String, String> quick;

  /// The [versionOf] each [quick] entry was made for. After an edit the old
  /// one (an older crop or filter) is never shown.
  final Map<String, int> quickVersions;

  /// What page [p] shows (round 10, P0-3): its display image; else
  /// Enhance's image of that look; else its thumbnail, stretched and
  /// softened (`blurred`) until the display image is saved;
  /// else null. Never the original or an unfiltered crop.
  ViewerImage? imageFor(ScanPage p) {
    final processed = p.processedPath;
    if (processed != null && File(processed).existsSync()) return (path: processed, blurred: false);
    final look = quickVersions[p.id] == versionOf(p) ? quick[p.id] : null;
    if (look != null) return (path: look, blurred: false);
    final thumb = p.thumbPath;
    if (thumb != null && File(thumb).existsSync()) return (path: thumb, blurred: true);
    return null;
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
    // Enhance's images, right after Done, stand in until the display images
    // are saved, so an edited page never shows its old crop.
    final quick = {...state.quick};
    final versions = {...state.quickVersions};
    for (final p in doc.pages) {
      if (state.imageFor(p) != null) continue;
      final ready = _previews.lookIfReady(p) ?? _previews.handedOff(p);
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
    unawaited(_render.ensureCaches(doc, first: state.current?.id).catchError((Object e) => debugPrint('cache: $e')));
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

  /// The filter most of [pages] use (round 11, P0-11: added pages start
  /// with it), or null for none.
  static FilterType? documentFilter(List<ScanPage> pages) {
    final n = <FilterType, int>{};
    for (final p in pages) {
      n[p.edits.filter] = (n[p.edits.filter] ?? 0) + 1;
    }
    if (n.isEmpty) return null;
    return n.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// Round 11, P0-11: the pages [ids] were just added (at the end). Moves
  /// them after [after] if given, and shows the first of them.
  Future<void> placeNewPages(List<String> ids, {String? after}) async {
    bool has(ViewerState s) => s.document != null && ids.every((id) => s.document!.pages.any((p) => p.id == id));
    if (!has(state)) {
      await stream.firstWhere(has).timeout(const Duration(seconds: 10), onTimeout: () => state);
    }
    if (!has(state) || isClosed) return;
    var order = [for (final p in state.pages) p.id];
    if (after != null && order.contains(after)) {
      final rest = [for (final id in order) if (!ids.contains(id)) id];
      final at = rest.indexOf(after) + 1;
      order = [...rest.sublist(0, at), ...ids, ...rest.sublist(at)];
      final err = await reorder(order);
      if (err != null || isClosed) return;
    }
    emit(state.copyWith(index: order.indexOf(ids.first)));
  }

  Future<Failure?> reorder(List<String> ids) async =>
      (await _reorder(state.document!.id, ids)).fold((f) => f, (_) => null);

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
