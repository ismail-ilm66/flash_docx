part of 'page_editor_bloc.dart';

enum EditorStatus { idle, loading, saving, saved, failed }

@immutable
class PageEditorState extends Equatable {
  PageEditorState({
    required this.args,
    required this.pages,
    this.index = 0,
    this.status = EditorStatus.idle,
    this.failure,

    /// Upright original preview per page id (crop UI background).
    this.basePreviews = const {},

    /// Fully rendered preview per page id, for the Enhance screen.
    this.enhancePreviews = const {},
    this.rendering = false,
    this.savedDocumentId,
    this.snaps = const {},
    this.quickPreviews = const {},
    bool? applyAll,
    this.filterThumbs = const {},
  }) : applyAll = applyAll ?? args.isNewDocument;

  final EditorArgs args;
  final List<ScanPage> pages;
  final int index;
  final EditorStatus status;
  final Failure? failure;
  final Map<String, String> basePreviews;
  final Map<String, String> enhancePreviews;
  final bool rendering;
  final String? savedDocumentId;

  /// Magnetic-edge candidates per page id.
  final Map<String, SnapCandidates> snaps;

  /// Fast crop-only placeholders per page id (P0-4).
  final Map<String, String> quickPreviews;

  /// "All N pages": look changes go to every page. On by default for a new
  /// scan (P1-1); kept across page changes.
  final bool applyAll;

  /// Real 160 px renders of each filter, per page id.
  final Map<String, Map<FilterType, String>> filterThumbs;

  /// The look Reset goes back to: Auto for documents, ID colour for ID /
  /// passport (fix list v4), brightness and contrast 0.
  FilterType get defaultFilter =>
      args.mode == ScanMode.document ? FilterType.auto : FilterType.idColor;

  bool _isDefault(PageEdits e) =>
      e.filter == defaultFilter && e.brightness == 0 && e.contrast == 0;

  /// Reset is enabled only when something differs from the default.
  bool get canReset => applyAll
      ? pages.any((p) => !_isDefault(p.edits))
      : (current != null && !_isDefault(current!.edits));

  /// What page [p] shows on Enhance: its exact render, else its last
  /// render, else its crop-only placeholder (never the uncropped photo).
  String? previewFor(ScanPage p) =>
      enhancePreviews[_previewKey(p)] ??
      enhancePreviews.entries
          .where((e) => e.key.startsWith('${p.id}:'))
          .map((e) => e.value)
          .lastOrNull ??
      quickPreviews[p.id];

  ScanPage? get current =>
      pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];
  PageEdits get edits => current?.edits ?? const PageEdits();
  String? get basePreview => current == null ? null : basePreviews[current!.id];
  String? get enhancePreview =>
      current == null ? null : enhancePreviews[_previewKey(current!)];

  /// What Enhance shows now (P0-4): the exact render, else the last render
  /// of this page (another filter), else the crop-only placeholder. Never
  /// the uncropped photo; null means "spinner".
  String? get shownPreview {
    final p = current;
    if (p == null) return null;
    return enhancePreview ??
        enhancePreviews.entries
            .where((e) => e.key.startsWith('${p.id}:'))
            .map((e) => e.value)
            .lastOrNull ??
        quickPreviews[p.id];
  }

  /// "Hold to compare": the same crop with no filter.
  String? get comparePreview =>
      current == null ? null : quickPreviews[current!.id];

  /// Sliders are excluded: they are applied live on the GPU, so moving them
  /// never needs a new render.
  static String _previewKey(ScanPage p) =>
      '${p.id}:${Object.hash(p.originalPath, p.edits.crop, p.edits.normalizedTurns, p.edits.filter)}';

  PageEditorState copyWith({
    List<ScanPage>? pages,
    int? index,
    EditorStatus? status,
    Failure? failure,
    bool clearFailure = false,
    Map<String, String>? basePreviews,
    Map<String, String>? enhancePreviews,
    bool? rendering,
    String? savedDocumentId,
    Map<String, SnapCandidates>? snaps,
    Map<String, String>? quickPreviews,
    bool? applyAll,
    Map<String, Map<FilterType, String>>? filterThumbs,
  }) {
    return PageEditorState(
      args: args,
      pages: pages ?? this.pages,
      index: index ?? this.index,
      status: status ?? this.status,
      failure: clearFailure ? null : failure ?? this.failure,
      basePreviews: basePreviews ?? this.basePreviews,
      enhancePreviews: enhancePreviews ?? this.enhancePreviews,
      rendering: rendering ?? this.rendering,
      savedDocumentId: savedDocumentId ?? this.savedDocumentId,
      snaps: snaps ?? this.snaps,
      quickPreviews: quickPreviews ?? this.quickPreviews,
      applyAll: applyAll ?? this.applyAll,
      filterThumbs: filterThumbs ?? this.filterThumbs,
    );
  }

  @override
  List<Object?> get props => [
    pages,
    index,
    status,
    failure,
    basePreviews,
    enhancePreviews,
    rendering,
    savedDocumentId,
    snaps,
    quickPreviews,
    applyAll,
    filterThumbs,
  ];
}
