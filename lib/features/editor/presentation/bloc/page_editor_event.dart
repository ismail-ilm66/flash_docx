part of 'page_editor_bloc.dart';

sealed class PageEditorEvent {
  const PageEditorEvent();
}

class EditorStarted extends PageEditorEvent {
  const EditorStarted(this.args);
  final EditorArgs args;
}

class EditorPageSelected extends PageEditorEvent {
  const EditorPageSelected(this.index);
  final int index;
}

class EditorCornerMoved extends PageEditorEvent {
  const EditorCornerMoved(this.corner, this.point);
  final int corner;
  final Pt point;
}

class EditorCornerDragEnded extends PageEditorEvent {
  const EditorCornerDragEnded();
}

/// The blurry-page banner hides itself after a few seconds (round 7, P0-4).
class EditorBlurryHidden extends PageEditorEvent {
  const EditorBlurryHidden(this.pageId);
  final String pageId;
}

/// Round 11, P1-11: look for fingers on the page with [pageId] (Enhance).
class EditorFingersRequested extends PageEditorEvent {
  const EditorFingersRequested(this.pageId);
  final String pageId;
}

/// "Remove" ([remove] true) or "Undo" on the current page's fingers.
class EditorFingersRemoved extends PageEditorEvent {
  const EditorFingersRemoved({required this.remove});
  final bool remove;
}

/// The "Fingers removed · Undo" chip's 4 s are over.
class EditorFingersChipHidden extends PageEditorEvent {
  const EditorFingersChipHidden();
}

/// Enhance was closed (back to Adjust edges).
class EditorEnhanceClosed extends PageEditorEvent {
  const EditorEnhanceClosed();
}

class EditorRotated extends PageEditorEvent {
  const EditorRotated({required this.clockwise});
  final bool clockwise;
}

class EditorAutoEdgesRequested extends PageEditorEvent {
  const EditorAutoEdgesRequested();
}

class EditorFilterChanged extends PageEditorEvent {
  const EditorFilterChanged(this.filter);
  final FilterType filter;
}

class EditorBrightnessChanged extends PageEditorEvent {
  const EditorBrightnessChanged(this.value);
  final double value;
}

class EditorContrastChanged extends PageEditorEvent {
  const EditorContrastChanged(this.value);
  final double value;
}

class EditorLookReset extends PageEditorEvent {
  const EditorLookReset();
}

/// The "All N pages" switch on Enhance (P1-1).
class EditorApplyAllToggled extends PageEditorEvent {
  const EditorApplyAllToggled(this.on);
  final bool on;
}

/// Render the six real filter thumbnails for the current page (P0-4 / P1-1).
class EditorFilterThumbsRequested extends PageEditorEvent {
  const EditorFilterThumbsRequested();
}

/// Draft pages appended to the current session (the strip's "+" tile).
class EditorPagesAdded extends PageEditorEvent {
  const EditorPagesAdded(this.pages);
  final List<ScanPage> pages;
}

class EditorPageDeleted extends PageEditorEvent {
  const EditorPageDeleted();
}

class EditorPageRetaken extends PageEditorEvent {
  const EditorPageRetaken(this.newOriginalPath, {this.guide, this.capture});
  final String newOriginalPath;
  final Quad? guide;
  final CaptureMeta? capture;
}

class EditorPreviewRequested extends PageEditorEvent {
  const EditorPreviewRequested({this.forEnhance = false});
  final bool forEnhance;
}

class EditorSaveRequested extends PageEditorEvent {
  const EditorSaveRequested();
}

/// A whole new crop from a mid-edge drag (P1-2); rejected if not convex.
class EditorCropChanged extends PageEditorEvent {
  const EditorCropChanged(this.quad);
  final Quad quad;
}

/// Compute magnetic-edge candidates for the current page (P1-3).
class EditorSnapsRequested extends PageEditorEvent {
  const EditorSnapsRequested();
}

/// Crop-only thumbnails for the Adjust edges page strip (P0-3).
class EditorStripThumbsRequested extends PageEditorEvent {
  const EditorStripThumbsRequested();
}

/// Round 11b, P0-18: a page that was still being prepared at Done is
/// ready (null: it couldn't be read).
class EditorPageArrived extends PageEditorEvent {
  const EditorPageArrived(this.order, this.page, {this.blurry = false});
  final int order;
  final ScanPage? page;
  final bool blurry;
}
