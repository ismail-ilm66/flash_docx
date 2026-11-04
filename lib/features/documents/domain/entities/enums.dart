enum ScanMode { single, batch, idCard, passport }

enum FilterType { original, auto, colorBoost, grayscale, bwPrint }

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
