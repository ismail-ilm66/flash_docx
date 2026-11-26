part of 'scan_session_bloc.dart';

enum SessionStatus { capturing, preparing, ready, failed }

enum CaptureStatus { processing, ready, failed }

class Capture extends Equatable {
  const Capture(
    this.id,
    this.path, {
    this.side,
    this.guide,
    this.capture,
    this.status = CaptureStatus.processing,
    this.page,
    this.sharpness,
    this.brightness,
    this.thumb,
    this.blurry = false,
  });

  final String id;

  /// A document page that's partly smeared or clearly unreadable (round 6
  /// P1-1, round 7 P0-4): Adjust edges offers a retake, once.
  final bool blurry;

  /// Raw photo from the camera (moved into place by the background job).
  final String path;
  final CardSide? side;

  /// On-screen guide frame in photo coordinates (ID / passport fallback and
  /// first search area).
  final Quad? guide;

  /// How the phone was held when it was taken (P0-1).
  final CaptureMeta? capture;
  final CaptureStatus status;

  /// The prepared draft page once [status] is ready.
  final ScanPage? page;
  final double? sharpness;
  final double? brightness;

  /// Small image for the page stack (P0-3): the crop-only 600 px preview
  /// once it's ready, never the uncropped photo; null shows a placeholder.
  final String? thumb;

  Capture copyWith({
    CaptureStatus? status,
    ScanPage? page,
    double? sharpness,
    double? brightness,
    String? thumb,
    bool? blurry,
  }) =>
      Capture(
        id,
        path,
        side: side,
        guide: guide,
        capture: capture,
        status: status ?? this.status,
        page: page ?? this.page,
        sharpness: sharpness ?? this.sharpness,
        brightness: brightness ?? this.brightness,
        thumb: thumb ?? this.thumb,
        blurry: blurry ?? this.blurry,
      );

  @override
  List<Object?> get props => [id, path, side, guide, capture, status, page, sharpness, brightness, thumb, blurry];
}

/// A post-capture prompt for one capture (round 3, A3).
enum NoticeKind { dark, unreadable }

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
    this.pending = const [],
  });

  /// Round 11b, P0-18: with [result], the photos still being prepared.
  final List<PendingPage> pending;

  final ScanMode mode;
  final List<Capture> captures;
  final bool flashOn;
  final SessionStatus status;
  final Failure? failure;

  /// Prepared draft pages, set when [status] is [SessionStatus.ready].
  final List<ScanPage>? result;

  /// Document pages that came out blurry (round 7, P0-4), by page id.
  Set<String> get blurryPages => {
    for (final c in captures)
      if (c.blurry && c.page != null) c.page!.id,
  };

  /// The last shot was dark (round 6, P1-1): a "Low light" chip until a
  /// brighter shot or the flash.
  bool get lowLight {
    if (flashOn) return false;
    for (final c in captures.reversed) {
      final b = c.brightness;
      if (b != null) return b < CaptureChecks.lowLightThreshold;
    }
    return false;
  }

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
    List<PendingPage>? pending,
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
        pending: pending ?? const [],
      );

  @override
  List<Object?> get props => [mode, captures, flashOn, status, failure, result, notice, insertAt, waitingForQueue, pending];
}
