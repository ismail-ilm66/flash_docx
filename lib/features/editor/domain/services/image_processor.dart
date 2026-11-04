import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';

/// Implemented with OpenCV in `data/`. All methods run off the UI isolate.
abstract interface class ImageProcessor {
  /// Finds the document corners. Returns null when no document-like shape is
  /// found. [snapAspectRatio] snaps the result to a known card ratio.
  Future<Quad?> detectEdges(String imagePath, {double? snapAspectRatio});

  /// Auto crop for a freshly captured or imported image.
  ///
  /// When nothing is found the crop becomes [fallback] (the on-screen guide
  /// frame in ID / passport modes) or a 5% inset, never the exact full frame.
  /// [filter] is the user's default filter from Settings.
  Future<AutoEditsResult> autoEdits(
    String imagePath, {
    double? snapAspectRatio,
    Quad? fallback,
    FilterType filter = FilterType.auto,
  });

  /// Renders [edits] onto the original and writes a JPEG/PNG to [outputPath].
  /// Returns the output path.
  Future<String> render(
    String originalPath,
    PageEdits edits, {
    required RenderSize size,
    required String outputPath,
    int jpegQuality,
  });

  /// Full-resolution crop + rotate → gray → mild contrast → denoise, for text
  /// recognition. Ignores the filter and sliders in [edits].
  Future<String> renderForOcr(
    String originalPath,
    PageEdits edits, {
    required String outputPath,
  });

  /// Normalises EXIF orientation (or to a new file) so that every later step
  /// can ignore EXIF. Returns the upright image path.
  Future<String> normalizeOrientation(String imagePath, {String? outputPath});

  /// Pixel size of an image without decoding it fully.
  Future<({int width, int height})> imageSize(String imagePath);
}

class AutoEditsResult {
  const AutoEditsResult({required this.edits, required this.detected});

  final PageEdits edits;

  /// False when the crop is a fallback and the user should be told to drag
  /// the corners.
  final bool detected;
}
