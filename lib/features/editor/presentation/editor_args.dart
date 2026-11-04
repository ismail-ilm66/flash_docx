import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// What the editor screens operate on.
///
/// * New scan: [documentId] is null, [pages] are drafts in the capture temp
///   folder. "Done" creates the document.
/// * Add pages: [documentId] set and [addingPages] true. "Done" appends.
/// * Edit existing: [documentId] set, [pages] are the saved pages. "Done"
///   updates them.
class EditorArgs {
  const EditorArgs({
    required this.pages,
    required this.mode,
    this.documentId,
    this.addingPages = false,
    this.initialIndex = 0,
    this.startAtEnhance = false,
  });

  final List<ScanPage> pages;
  final ScanMode mode;
  final String? documentId;
  final bool addingPages;
  final int initialIndex;
  final bool startAtEnhance;

  bool get isNewDocument => documentId == null;

  EditorArgs copyWith({
    List<ScanPage>? pages,
    int? initialIndex,
    bool? startAtEnhance,
  }) =>
      EditorArgs(
        pages: pages ?? this.pages,
        mode: mode,
        documentId: documentId,
        addingPages: addingPages,
        initialIndex: initialIndex ?? this.initialIndex,
        startAtEnhance: startAtEnhance ?? this.startAtEnhance,
      );
}
