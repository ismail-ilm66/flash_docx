part of 'scan_session_bloc.dart';

sealed class ScanSessionEvent {
  const ScanSessionEvent();
}

class SessionModeChanged extends ScanSessionEvent {
  const SessionModeChanged(this.mode);
  final ScanMode mode;
}

class SessionFlashToggled extends ScanSessionEvent {
  const SessionFlashToggled();
}

/// A photo was just taken. Only records it; processing is queued.
class SessionCaptured extends ScanSessionEvent {
  const SessionCaptured(this.path, {this.guide, this.capture, this.live});
  final String path;
  final Quad? guide;

  /// Round 11c, B2: the live outline at the shutter (portrait screen
  /// frame): the page's corners if detection finds none.
  final Quad? live;

  /// What the camera knew at the shutter; made upright at ingest (P0-1).
  final CaptureMeta? capture;
}

/// Background processing of one capture finished (internal).
class _CaptureProcessed extends ScanSessionEvent {
  const _CaptureProcessed(this.id, this.page, this.result, this.failure);
  final String id;
  final ScanPage? page;
  final AutoEditsResult? result;
  final Failure? failure;
}

/// The crop-only stack thumbnail for a capture is ready (P0-3).
class _CaptureThumbReady extends ScanSessionEvent {
  const _CaptureThumbReady(this.id, this.path);
  final String id;
  final String path;
}

class SessionCaptureRemoved extends ScanSessionEvent {
  const SessionCaptureRemoved(this.index);
  final int index;
}

/// "Retake" on a blurry-photo notice: drop that capture; the next shot takes
/// its place in the page order.
class SessionRetakeRequested extends ScanSessionEvent {
  const SessionRetakeRequested(this.captureId);
  final String captureId;
}

class SessionNoticeDismissed extends ScanSessionEvent {
  const SessionNoticeDismissed();
}

class SessionImported extends ScanSessionEvent {
  const SessionImported(this.paths);
  final List<String> paths;
}

/// "Done": waits for the queue, then hands the pages to the editor.
class SessionFinished extends ScanSessionEvent {
  const SessionFinished({this.waitAll = false});

  /// Wait until every photo is prepared (pages handed back to a caller).
  /// Otherwise Adjust edges opens at once and the rest join it (round 11b,
  /// P0-18).
  final bool waitAll;
}

class SessionReset extends ScanSessionEvent {
  const SessionReset();
}
