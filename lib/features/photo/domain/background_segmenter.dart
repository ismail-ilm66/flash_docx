import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Finds the person in a passport photo (round 5 follow-up), so the
/// background can be changed and Enhance can tell skin from wall.
abstract interface class BackgroundSegmenter {
  /// An 8-bit person mask (255 = person) for the upright photo at
  /// [photoPath], as a PNG; null when segmentation isn't available on this
  /// phone (the background options are then hidden).
  ///
  /// With [focus] (the passport crop) only that part, plus a margin, is
  /// segmented: the model sees the head at several times the resolution,
  /// so hair and ears come out much sharper. It is pasted into [coarse]
  /// (the whole-photo mask) so the result still covers the whole photo.
  Future<String?> maskFor(String photoPath, {Quad? focus, String? coarse});
}
