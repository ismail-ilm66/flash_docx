/// Physical sizes in millimetres. Used by print layouts and PDF export.
abstract final class PaperMm {
  static const double a4Width = 210;
  static const double a4Height = 297;
  static const double letterWidth = 215.9;
  static const double letterHeight = 279.4;

  /// 4 × 6 in photo paper.
  static const double photo4x6Width = 101.6;
  static const double photo4x6Height = 152.4;
}

/// ISO/IEC 7810 card sizes in millimetres.
abstract final class CardMm {
  /// ID-1: CNIC, driving licence, bank card.
  static const double id1Width = 85.6;
  static const double id1Height = 54;

  /// ID-3: passport data page.
  static const double id3Width = 125;
  static const double id3Height = 88;

  static const double id1Aspect = id1Width / id1Height;
  static const double id3Aspect = id3Width / id3Height;
}

abstract final class RenderPx {
  static const int thumbLongEdge = 300;
  /// Editor previews (round 3: 1200 px).
  static const int previewLongEdge = 1200;
  /// Round 11c, B2: the work copy made right after each photo (Adjust
  /// edges' picture, corner detection, the crop-only previews).
  static const int workLongEdge = 1000;
  /// The finished page the viewer shows (round 10, P0-3), saved with the
  /// page: crop, filter and border clean-up at 1600 px.
  static const int displayLongEdge = 1600;
  /// "Standard — smaller file, for sharing" (round 3).
  static const int standardExportLongEdge = 2000;
  static const int detectionLongEdge = 800;
  static const int printDpi = 300;
}

abstract final class Limits {
  static const int sliderMin = -100;
  static const int sliderMax = 100;
  static const int sliderDebounceMs = 80;
  static const int maxBatchPages = 100;
  /// Round 10, P1-1: Standard = 2000 px at q80, High = 3000 px at q92, so
  /// the two really differ.
  static const int standardJpegQuality = 80;
  static const int highJpegQuality = 92;
  static const int cacheJpegQuality = 90;
  /// The viewer's display image and the thumbnail (round 10, P0-3).
  static const int displayJpegQuality = 85;
  static const int thumbJpegQuality = 80;
}
