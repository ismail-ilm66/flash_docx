/// Physical sizes in millimetres. Used by print layouts and PDF export.
abstract final class PaperMm {
  static const double a4Width = 210;
  static const double a4Height = 297;
  static const double letterWidth = 215.9;
  static const double letterHeight = 279.4;
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
  static const int previewLongEdge = 1600;
  /// A4 at 300 DPI on the long edge.
  static const int standardExportLongEdge = 2480;
  static const int detectionLongEdge = 1000;
  static const int printDpi = 300;
}

abstract final class Limits {
  static const int sliderMin = -100;
  static const int sliderMax = 100;
  static const int sliderDebounceMs = 80;
  static const int maxBatchPages = 100;
  static const int standardJpegQuality = 85;
  static const int highJpegQuality = 95;
  static const int cacheJpegQuality = 90;
}
