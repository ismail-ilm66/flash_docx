part of 'scan_session_bloc.dart';

enum SessionStatus { capturing, preparing, ready, failed }

enum CaptureStatus { processing, ready, failed }

class Capture extends Equatable {
  const Capture(
    this.id,
    this.path, {
    this.side,
    this.guide,
    this.status = CaptureStatus.processing,
    this.page,
    this.sharpness,
    this.brightness,
  });

  final String id;

  /// Raw photo from the camera (moved into place by the background job).
  final String path;
  final CardSide? side;

  /// On-screen guide frame in photo coordinates (ID / passport fallback and
  /// first search area).
  final Quad? guide;
  final CaptureStatus status;

  /// The prepared draft page once [status] is ready.
  final ScanPage? page;
  final double? sharpness;
  final double? brightness;

  /// Small image for the page stack: the 1200 px preview once ready.
  String? thumbPath(FileStore files) =>
      page == null ? null : files.basePreviewPath(page!.id, page!.originalPath);

  Capture copyWith({
    CaptureStatus? status,
    ScanPage? page,
    double? sharpness,
    double? brightness,
  }) =>
      Capture(
        id,
        path,
        side: side,
        guide: guide,
        status: status ?? this.status,
        page: page ?? this.page,
        sharpness: sharpness ?? this.sharpness,
        brightness: brightness ?? this.brightness,
      );

  @override
  List<Object?> get props => [id, path, side, guide, status, page, sharpness, brightness];
}

/// A post-capture prompt for one capture (round 3, A3).
enum NoticeKind { blurry, dark, unreadable }

class CaptureNotice extends Equatable {
  const CaptureNotice(this.kind, this.captureId);
  final NoticeKind kind;
  final String captureId;
  @override
  List<Object?> get props => [kind, captureId];
}

class ScanSessionState extends Equatable {
  const ScanSessionState({
    required this.mode,
    this.captures = const [],
    this.flashOn = false,
    this.status = SessionStatus.capturing,
    this.failure,
    this.result,
    this.notice,
    this.insertAt,
    this.waitingForQueue = false,
  });

  final ScanMode mode;
  final List<Capture> captures;
  final bool flashOn;
  final SessionStatus status;
  final Failure? failure;

  /// Prepared draft pages, set when [status] is [SessionStatus.ready].
  final List<ScanPage>? result;

  /// Prompt to show for the most recent problem capture, if any.
  final CaptureNotice? notice;

  /// After a "Retake", the next capture goes here instead of at the end.
  final int? insertAt;

  /// "Done" was pressed and is waiting for background processing.
  final bool waitingForQueue;

  ScanModeRules get rules => ScanModeRules.of(mode);
  int get count => captures.length;
  int get processed => captures.where((c) => c.status != CaptureStatus.processing).length;
  bool get isComplete => rules.isComplete(count);
  bool get canFinish => count > 0 && (isComplete || rules.canFinishEarly);
  bool get canCapture => !isComplete && status == SessionStatus.capturing && !waitingForQueue;
  GuideLabel get guide => rules.guideLabel(insertAt ?? count);

  /// Side of the next capture (ID card): the retaken slot or the next one.
  CardSide? get nextSide {
    final sides = rules.sides;
    final slot = insertAt ?? count;
    if (sides == null || slot >= sides.length) return null;
    return sides[slot];
  }

  ScanSessionState copyWith({
    ScanMode? mode,
    List<Capture>? captures,
    bool? flashOn,
    SessionStatus? status,
    Failure? failure,
    List<ScanPage>? result,
    CaptureNotice? notice,
    bool clearNotice = false,
    int? insertAt,
    bool clearInsertAt = false,
    bool? waitingForQueue,
  }) =>
      ScanSessionState(
        mode: mode ?? this.mode,
        captures: captures ?? this.captures,
        flashOn: flashOn ?? this.flashOn,
        status: status ?? this.status,
        failure: failure,
        result: result,
        notice: clearNotice ? null : notice ?? this.notice,
        insertAt: clearInsertAt ? null : insertAt ?? this.insertAt,
        waitingForQueue: waitingForQueue ?? this.waitingForQueue,
      );

  @override
  List<Object?> get props => [mode, captures, flashOn, status, failure, result, notice, insertAt, waitingForQueue];
}
