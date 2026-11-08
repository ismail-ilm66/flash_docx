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
