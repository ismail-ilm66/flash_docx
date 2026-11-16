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
    this.quickShapes = const {},
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

  /// The [shapeOf] each [quickPreviews] entry was made for: a placeholder
  /// of an older crop is not the page's shape any more.
  final Map<String, int> quickShapes;

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

  /// What page [p] shows on Enhance (round 6, P0-2: never the raw photo,
  /// never another crop): its finished look, else its instant image for
  /// this filter, else a look of the same crop in another filter. Null
  /// (a spinner) until one exists.
  String? previewFor(ScanPage p) {
    final exact = enhancePreviews[_previewKey(p)] ?? enhancePreviews[_instantKey(p)];
    if (exact != null) return exact;
    final shape = '${p.id}:${shapeOf(p)}:';
    String? sameShape;
    for (final e in enhancePreviews.entries) {
      if (e.key.startsWith(shape)) sameShape = e.value;
    }
    return sameShape;
  }

  /// [p]'s crop-only placeholder, only if it was made for its current crop.
  String? quickFor(ScanPage p) =>
      quickShapes[p.id] == shapeOf(p) ? quickPreviews[p.id] : null;

  ScanPage? get current =>
      pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];
  PageEdits get edits => current?.edits ?? const PageEdits();
  String? get basePreview => current == null ? null : basePreviews[current!.id];
  String? get enhancePreview =>
      current == null ? null : enhancePreviews[_previewKey(current!)];

  /// What Enhance shows now (P0-4): see [previewFor]. Null means "spinner".
  String? get shownPreview => current == null ? null : previewFor(current!);

  /// "Hold to compare": the same crop with no filter.
  String? get comparePreview => current == null
      ? null
      : quickFor(current!) ?? quickPreviews[current!.id];

  /// Crop, rotation and output shape: what a page's previews look like
  /// before the filter. In-memory keys only (not stable across launches).
  static int shapeOf(ScanPage p) => Object.hash(
    p.originalPath,
    p.edits.crop,
    p.edits.normalizedTurns,
    p.edits.outputAspect,
  );

  /// Sliders are excluded: they are applied live on the GPU, so moving them
  /// never needs a new render.
  static String _previewKey(ScanPage p) =>
      '${p.id}:${shapeOf(p)}:${p.edits.filter.name}';

  /// The instant image shown while [p]'s cleaned base is being made.
  static String _instantKey(ScanPage p) => '${_previewKey(p)}~instant';

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
    Map<String, int>? quickShapes,
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
      quickShapes: quickShapes ?? this.quickShapes,
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
    quickShapes,
    applyAll,
    filterThumbs,
  ];
}
