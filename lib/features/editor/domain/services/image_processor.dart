import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';

/// Implemented with OpenCV in `data/`. All methods run off the UI isolate.
abstract interface class ImageProcessor {
  /// Finds the document corners. Returns null when no 4-point contour that
  /// looks like a document is found.
  Future<Quad?> detectEdges(String imagePath, {double? snapAspectRatio});

  /// Auto crop + rotate + default filter for a freshly captured image.
  Future<PageEdits> autoEdits(String imagePath, {double? snapAspectRatio});

  /// Renders [edits] onto the original and writes a JPEG to [outputPath].
  /// Returns the output path.
  Future<String> render(
    String originalPath,
    PageEdits edits, {
    required RenderSize size,
    required String outputPath,
    int jpegQuality,
  });

  /// Normalises EXIF orientation in place (or to a new file) so that every
  /// later step can ignore EXIF. Returns the upright image path.
  Future<String> normalizeOrientation(String imagePath, {String? outputPath});

  /// Pixel size of an image without decoding it fully.
  Future<({int width, int height})> imageSize(String imagePath);
}
