import 'package:flash_dox/core/perf/perf_log.dart';

/// Round 11c, C2: four switches for timing runs on the test phone
/// (Settings → About → long-press the version). Never shown in a normal
/// release build ([PerfLog.enabled]), where they all stay on.
abstract final class DebugSwitches {
  static bool liveOutline = true;

  /// `warp_curved` (off: the plain 4-corner warp).
  static bool bentPages = true;
  static bool fingers = true;

  /// The grain cleaner (`_despeckle_L`).
  static bool grain = true;

  static Map<String, bool> toMap() => {'liveOutline': liveOutline, 'bentPages': bentPages, 'fingers': fingers, 'grain': grain};

  /// In the worker isolate: the switches the main isolate sent.
  static void apply(Map<String, bool> m) {
    liveOutline = m['liveOutline'] ?? true;
    bentPages = m['bentPages'] ?? true;
    fingers = m['fingers'] ?? true;
    grain = m['grain'] ?? true;
  }

  /// A short label for the log ("bent-page off").
  static String describe() {
    final off = [
      if (!liveOutline) 'live outline',
      if (!bentPages) 'bent-page flattening',
      if (!fingers) 'finger detection',
      if (!grain) 'grain cleaner',
    ];
    return off.isEmpty ? 'all on' : '${off.join(', ')} off';
  }
}
