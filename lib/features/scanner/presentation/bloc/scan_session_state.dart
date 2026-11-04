part of 'scan_session_bloc.dart';

enum SessionStatus { capturing, preparing, ready, failed }

class Capture extends Equatable {
  const Capture(this.path, {this.side});
  final String path;
  final CardSide? side;
  @override
  List<Object?> get props => [path, side];
}

class ScanSessionState extends Equatable {
  const ScanSessionState({
    required this.mode,
    this.captures = const [],
    this.flashOn = false,
    this.status = SessionStatus.capturing,
    this.failure,
    this.result,
  });

  final ScanMode mode;
  final List<Capture> captures;
  final bool flashOn;
  final SessionStatus status;
  final Failure? failure;

  /// Prepared draft pages, set when [status] is [SessionStatus.ready].
  final List<ScanPage>? result;

  ScanModeRules get rules => ScanModeRules.of(mode);
  int get count => captures.length;
  bool get isComplete => rules.isComplete(count);
  bool get canFinish => count > 0 && (isComplete || rules.canFinishEarly);
  bool get canCapture => !isComplete && status == SessionStatus.capturing;
  GuideLabel get guide => rules.guideLabel(count);
  CardSide? get nextSide {
    final sides = rules.sides;
    if (sides == null || count >= sides.length) return null;
    return sides[count];
  }

  ScanSessionState copyWith({
    ScanMode? mode,
    List<Capture>? captures,
    bool? flashOn,
    SessionStatus? status,
    Failure? failure,
    List<ScanPage>? result,
  }) =>
      ScanSessionState(
        mode: mode ?? this.mode,
        captures: captures ?? this.captures,
        flashOn: flashOn ?? this.flashOn,
        status: status ?? this.status,
        failure: failure,
        result: result,
      );

  @override
  List<Object?> get props => [mode, captures, flashOn, status, failure, result];
}
