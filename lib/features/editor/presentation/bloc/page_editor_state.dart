part of 'page_editor_bloc.dart';

enum EditorStatus { idle, loading, saving, saved, failed }

@immutable
class PageEditorState extends Equatable {
  const PageEditorState({
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
    this.appliedToAllTick = 0,
  });

  final EditorArgs args;
  final List<ScanPage> pages;
  final int index;
  final EditorStatus status;
  final Failure? failure;
  final Map<String, String> basePreviews;
  final Map<String, String> enhancePreviews;
  final bool rendering;
  final String? savedDocumentId;
  final int appliedToAllTick;

  ScanPage? get current => pages.isEmpty ? null : pages[index.clamp(0, pages.length - 1)];
  PageEdits get edits => current?.edits ?? const PageEdits();
  String? get basePreview => current == null ? null : basePreviews[current!.id];
  String? get enhancePreview =>
      current == null ? null : enhancePreviews[_previewKey(current!)];

  static String _previewKey(ScanPage p) => '${p.id}:${p.edits.hashCode}';

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
    int? appliedToAllTick,
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
      appliedToAllTick: appliedToAllTick ?? this.appliedToAllTick,
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
        appliedToAllTick,
      ];
}
