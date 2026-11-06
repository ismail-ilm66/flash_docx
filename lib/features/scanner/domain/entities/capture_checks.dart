/// Thresholds for the post-capture checks (round 3, A3).
///
/// PROVISIONAL. The list asks for these to be calibrated on real
/// full-resolution captures from three phones; every capture logs its
/// `sharpness` and `brightness` (`[ingest] …` in debug logs) for that.
/// Sharpness is the Laplacian variance on a 1000 px copy of the photo.
abstract final class CaptureChecks {
  /// Below this, "Photo looks blurry — Retake / Keep".
  static const double blurThreshold = 35;

  /// ID / passport (P0-2): below this, "Card looks blurry — Retake / Keep".
  /// Measured on the warped card at 1000 px wide. Calibrated on the
  /// reference test photos: sharp 41–63, Gaussian-blurred (σ 1.5) 10–21.
  /// Those photos are small screenshots, so real full-resolution card shots
  /// score higher: re-check on the owner's phones (`[ingest] … card …` log).
  static const double cardBlurThreshold = 25;

  static bool isCardBlurry(double? sharpness) => sharpness != null && sharpness < cardBlurThreshold;

  /// Below this mean gray level (0..255), suggest the flash.
  static const double darkThreshold = 60;

  static bool isBlurry(double? sharpness) => sharpness != null && sharpness < blurThreshold;
  static bool isDark(double? brightness) => brightness != null && brightness < darkThreshold;
}
