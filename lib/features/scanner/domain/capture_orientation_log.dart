/// The `[orient]` line of each captured page (round 5, P0-1), kept so dev
/// builds can print it on Adjust edges: only the owner has the phone that
/// fails, and a screenshot is easier than `adb`. In memory only.
abstract final class CaptureOrientationLog {
  static final Map<String, String> _byPage = {};

  static void record(String pageId, String line) => _byPage[pageId] = line;

  static String? lineFor(String pageId) => _byPage[pageId];
}
