import 'package:flutter/foundation.dart';

/// Per-step timings for the `[step]` log lines, so a slow phone's log shows
/// where the time goes (decode, filter, encode, PDF…). Dev and profile
/// builds only.
///
/// Each [lap] records the time since the previous lap (or the start).
class StepTimer {
  StepTimer(this.label);

  final String label;
  final _sw = Stopwatch()..start();
  final _laps = <String>[];
  int _last = 0;

  int get elapsedMs => _sw.elapsedMilliseconds;

  void lap(String step) {
    final now = _sw.elapsedMilliseconds;
    _laps.add('$step ${now - _last}');
    _last = now;
  }

  /// Prints one line, e.g.
  /// `[step] render 2000 px q85: decode 4000×3000 420 · … | total 1900 ms`.
  /// Checks `kReleaseMode` itself: on the worker isolate bootstrap's silent
  /// `debugPrint` doesn't apply.
  void report() {
    if (kReleaseMode) return;
    debugPrint('[step] $label: ${_laps.join(' · ')} | total ${_sw.elapsedMilliseconds} ms');
  }
}
