import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Round 10, P1-6: "Scanned with Flash Dox: Document Scanner" in the
/// bottom-right corner of every exported document page, like CamScanner. On
/// by default and free to turn off. Drawn only at export, never on the
/// stored page, so turning it off works on old documents too.
abstract final class PageFooter {
  static const text = 'Scanned with Flash Dox: Document Scanner';

  /// The store page. (The fix list wrote `com.swatnoa…`; the app id is
  /// `com.swtnoa.flashdox`.)
  static const url = 'https://play.google.com/store/apps/details?id=com.swtnoa.flashdox';

  static const double logoMm = 4;
  static const double textPt = 7;
  static const double marginMm = 6;
  static const double gapMm = 1.5;
  static const int color = 0xFF8A8A8A;

  /// The white pill behind it, so it reads on any content.
  static const double pillRadiusMm = 2;
  static const double pillPadVMm = 1.5;
  static const double pillPadHMm = 3;
  static const double pillOpacity = 0.85;

  /// Logo height in a JPG / PNG page: 1.6 % of the image height; the rest
  /// scales with it.
  static const double imageLogoFraction = 0.016;

  /// Document pages only: never ID cards or passports (people hand those to
  /// offices), passport photos or extracted text.
  static bool appliesTo(ScanDocument doc) => doc.mode == ScanMode.document;

  /// A signature (or a date) where the footer goes moves it to the
  /// bottom-left. The footer covers about the right 45 % of the width and
  /// the bottom 8 % of the height.
  static bool onLeft(PageEdits e) => e.overlays.any((o) => o.left + o.width > 0.55 && o.top + o.height > 0.92);
}
