import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';

/// Implemented with OpenCV in `data/`. All methods run off the UI isolate.
abstract interface class ImageProcessor {
  /// Finds the document corners. Returns null when no document-like shape is
  /// found. [snapAspectRatio] snaps the result to a known card ratio.
  Future<Quad?> detectEdges(String imagePath, {double? snapAspectRatio});

  /// The one job per new photo (camera, Photos, Files, share-in): decode
  /// once, write the upright original to [originalOut] and the editor's base
  /// preview to [previewOut], detect the document, and return the auto edits.
  /// When nothing is found the crop becomes [fallback] (the on-screen guide
  /// frame in ID / passport modes) or a 5% inset, never the exact full frame.
  /// [filter] is the user's default filter from Settings.
  Future<AutoEditsResult> ingest(
    String sourcePath, {
    required String originalOut,
    required String previewOut,
    double? snapAspectRatio,
    Quad? fallback,
    FilterType filter = FilterType.auto,
  });

  /// Enhance preview (filter only; sliders are applied live in the UI).
  /// [workPath] caches the cropped page at preview size between calls.
  Future<String> renderLook(
    String originalPath,
    PageEdits edits, {
    required String workPath,
    required String outputPath,
  });

  /// Processed preview + thumbnail for the viewer, from one decode.
  Future<void> renderPageCaches(
    String originalPath,
    PageEdits edits, {
    required String processedOut,
    required String thumbOut,
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
