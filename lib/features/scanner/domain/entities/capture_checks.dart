/// Thresholds for the post-capture checks (round 3, A3).
///
/// PROVISIONAL. The list asks for these to be calibrated on real
/// full-resolution captures from three phones; every capture logs its
/// `sharpness` and `brightness` (`[ingest] …` in debug logs) for that.
/// Sharpness is the Laplacian variance on a 1000 px copy of the photo.
abstract final class CaptureChecks {
  /// Below this a document page is clearly unreadable: "This page looks
  /// blurry · Retake" on Adjust edges (round 7, P0-4). Was 35, which warned
  /// on steady shots (10–12 prompts for 8 pages). The one Y9 Prime page
  /// measured so far scored 120. TODO(round 7): calibrate on 20 normal
  /// photos from the test phone so that none of them warns.
  static const double blurThreshold = 15;

  /// Below this mean gray level (0..255), suggest the flash.
  static const double darkThreshold = 60;

  /// Round 6, P1-1: below this, the camera shows "Low light: turn on
  /// flash" until a brighter shot (the fix list's 70 of 255).
  static const double lowLightThreshold = 70;

  static bool isBlurry(double? sharpness) => sharpness != null && sharpness < blurThreshold;
  static bool isDark(double? brightness) => brightness != null && brightness < darkThreshold;
}
