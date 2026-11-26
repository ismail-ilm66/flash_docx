/// Finds the face in a passport photo (round 11b, P1-14), for Enhance's
/// face brightening.
abstract interface class FaceLocator {
  /// The largest face in the upright photo at [photoPath], as
  /// [x0, y0, x1, y1] fractions of it; null when none is found or face
  /// detection isn't available on this phone.
  Future<List<double>?> faceBox(String photoPath);
}
