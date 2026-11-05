/// Thresholds for the post-capture checks (round 3, A3).
///
/// PROVISIONAL. The list asks for these to be calibrated on real
/// full-resolution captures from three phones; every capture logs its
/// `sharpness` and `brightness` (`[ingest] …` in debug logs) for that.
/// Sharpness is the Laplacian variance on a 1000 px copy of the photo.
abstract final class CaptureChecks {
  /// Below this, "Photo looks blurry — Retake / Keep".
  static const double blurThreshold = 35;

  /// Below this mean gray level (0..255), suggest the flash.
  static const double darkThreshold = 60;

  static bool isBlurry(double? sharpness) => sharpness != null && sharpness < blurThreshold;
  static bool isDark(double? brightness) => brightness != null && brightness < darkThreshold;
}
