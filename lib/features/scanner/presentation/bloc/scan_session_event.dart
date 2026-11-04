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

class SessionCaptured extends ScanSessionEvent {
  const SessionCaptured(this.path, {this.guide});
  final String path;
  final Quad? guide;
}

class SessionCaptureRemoved extends ScanSessionEvent {
  const SessionCaptureRemoved(this.index);
  final int index;
}

class SessionImported extends ScanSessionEvent {
  const SessionImported(this.paths);
  final List<String> paths;
}

class SessionFinished extends ScanSessionEvent {
  const SessionFinished();
}

class SessionReset extends ScanSessionEvent {
  const SessionReset();
}
