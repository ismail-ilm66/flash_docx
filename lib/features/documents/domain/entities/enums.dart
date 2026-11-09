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
/// old "lightBlue" (first build) reads as dark blue.
enum PhotoBackground { original, white, darkBlue }

/// Home folders (round 4, feature 3). Stored by index: append only (office
/// came in round 5). Display order is `FolderChips.order`.
enum DocFolder { other, bills, ids, education, receipts, office }

extension ScanModeX on ScanMode {
  bool get supportsPrintLayout =>
      this == ScanMode.idCard || this == ScanMode.passport;

  /// Offered as a chip on the camera.
  bool get isCameraMode => this != ScanMode.photo;
}
