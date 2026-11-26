import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';

/// A page still being prepared when Adjust edges opened (round 11b,
/// P0-18): its place among the pages ([ScanPage.order]) and the page, with
/// whether the shot came out blurry; null if it couldn't be read.
typedef PendingPage = ({int order, Future<({ScanPage page, bool blurry})?> page});

/// What the editor screens operate on.
///
/// * New scan: [documentId] is null, [pages] are drafts in the draft folder
///   (kept on disk until Done or Discard, round 7). "Done" creates the
///   document.
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
    this.tool,
    this.blurryPages = const {},
    this.pending = const [],
  });

  /// Pages that join while Adjust edges is open (round 11b, P0-18).
  final List<PendingPage> pending;

  /// Shots that came out partly blurry (round 6, P1-1): Adjust edges offers
  /// a retake for these page ids.
  final Set<String> blurryPages;

  /// A new scan made for a Home tool: Done opens the tool (P1-4).
  final ToolTarget? tool;

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
        tool: tool,
        blurryPages: blurryPages,
        pending: pending,
      );
}
