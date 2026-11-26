import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// The "Flash Dox: Document Scanner" footer on exported document pages
/// (round 10, P1-6; round 11 style, artboard *FooterBadge*). It sits in its
/// own white band under the page, so it never covers the scan: a black
/// rounded square with the white logo mark and the name beside it,
/// right-aligned. On by default and free to turn off. Drawn only at export,
/// never on the stored page.
abstract final class PageFooter {
  static const brand = 'Flash Dox';
  static const tagline = ': Document Scanner';
  static const text = '$brand$tagline';

  /// The store page. (The fix list wrote `com.swatnoa…`; the app id is
  /// `com.swtnoa.flashdox`.)
  static const url = 'https://play.google.com/store/apps/details?id=com.swtnoa.flashdox';

  /// PDF: the band under the page content.
  static const double bandMm = 10;

  /// The black rounded square and the white mark inside it.
  static const double squareMm = 6;
  static const double squareRadiusMm = 1.6;
  static const double markMm = 4.4;
  static const int squareColor = 0xFF111111;

  /// Text beside the square: 9 pt, ExtraBold "Flash Dox", SemiBold the rest.
  static const double gapMm = 2;
  static const double textPt = 9;
  static const int textColor = 0xFF111111;

  /// From the right edge of the page.
  static const double rightMm = 6;

  /// JPG / PNG: a white strip this share of the image height goes under it;
  /// the badge keeps the PDF band's proportions inside it.
  static const double imageStripFraction = 0.04;

  /// Document pages only: never ID cards or passports (people hand those to
  /// offices), passport photos or extracted text.
  static bool appliesTo(ScanDocument doc) => doc.mode == ScanMode.document;
}
