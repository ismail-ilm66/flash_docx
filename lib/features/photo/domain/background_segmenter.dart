/// Finds the person in a passport photo (round 5 follow-up), so the
/// background can be made white or light blue.
abstract interface class BackgroundSegmenter {
  /// An 8-bit person mask (255 = person) for the upright photo at [photoPath],
  /// as a PNG; null when segmentation isn't available on this phone (the
  /// White / Light blue options are then hidden).
  Future<String?> maskFor(String photoPath);
}
