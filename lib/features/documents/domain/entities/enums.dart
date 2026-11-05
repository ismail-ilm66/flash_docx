/// Stored in the database by index; v2 schema migrates the old
/// `single, batch, idCard, passport` values (see AppDatabase.migration).
enum ScanMode { document, idCard, passport }

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
}

extension ScanModeX on ScanMode {
  bool get supportsPrintLayout =>
      this == ScanMode.idCard || this == ScanMode.passport;
}
