/// Stored in the database by index (append only); v2 schema migrates the
/// old `single, batch, idCard, passport` values (see AppDatabase.migration).
/// [photo] is a passport-size photo (feature 5), made from Tools, not the
/// camera's mode chips.
enum ScanMode { document, idCard, passport, photo }

enum FilterType { original, auto, idColor, colorBoost, grayscale, bwPrint }

enum CardSide { front, back }

enum ActivityType {
  created,
  edited,
  sharedPdf,
  sharedImages,
  savedToPhone,
  textCopied,
  printLayout,
  // Append only: stored by index.
  signed,
  photoSheet,
}

/// Passport photo background. Stored by name in the page's edits JSON; an
/// old "lightBlue" (first build) reads as dark blue. Round 10 (P1-7) added
/// the usual light shades; the new "Light blue" is stored as `paleBlue` so
/// those old photos keep their colour. [PhotoBackgrounds.shown] is the
/// display order.
enum PhotoBackground { original, white, darkBlue, offWhite, paleBlue, skyBlue }

abstract final class PhotoBackgrounds {
  /// White · Off-white · Light blue · Sky blue · Dark blue · Original.
  static const List<PhotoBackground> shown = [
    PhotoBackground.white,
    PhotoBackground.offWhite,
    PhotoBackground.paleBlue,
    PhotoBackground.skyBlue,
    PhotoBackground.darkBlue,
    PhotoBackground.original,
  ];

  /// The colour as 0xAARRGGBB; null for the photo's own background.
  static int? argb(PhotoBackground b) => switch (b) {
    PhotoBackground.original => null,
    PhotoBackground.white => 0xFFFFFFFF,
    PhotoBackground.offWhite => 0xFFF2F2F2,
    PhotoBackground.paleBlue => 0xFFCFE2F3,
    PhotoBackground.skyBlue => 0xFF9CC3E6,
    PhotoBackground.darkBlue => 0xFF1F4E8C,
  };
}

/// Passport photo touch-up: light and colour fixed, skin softened (smooth
/// more than natural), eyes and hair sharpened. Stored by name.
enum PhotoEnhance { off, natural, smooth }

/// Home folders (round 4, feature 3). Stored by index: append only (office
/// came in round 5). Display order is `FolderChips.order`.
enum DocFolder { other, bills, ids, education, receipts, office }

extension ScanModeX on ScanMode {
  bool get supportsPrintLayout =>
      this == ScanMode.idCard || this == ScanMode.passport;

  /// Offered as a chip on the camera.
  bool get isCameraMode => this != ScanMode.photo;
}
