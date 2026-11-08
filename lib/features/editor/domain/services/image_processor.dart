import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/snap_guide.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';

/// Implemented with OpenCV in `data/`. All methods run off the UI isolate.
abstract interface class ImageProcessor {
  /// Finds the document corners. Returns null when no document-like shape is
  /// found. [snapAspectRatio] snaps the result to a known card ratio.
  Future<Quad?> detectEdges(String imagePath, {double? snapAspectRatio});

  /// The one job per new photo (camera, Photos, Files, share-in). The
  /// original at [sourcePath] is never modified. Writes the editor's base
  /// preview to [previewOut], detects the document, measures sharpness and
  /// brightness, and returns the auto edits.
  ///
  /// When nothing is found the crop becomes [guide] (the on-screen frame in
  /// ID / passport modes, which is also searched first) or a 5 % inset.
  /// [outputAspect] forces the warp to the real card shape. [capture] is what
  /// the camera knew at the shutter (P0-1; null for imports): the original is
  /// made upright from it and the EXIF tag, and [guide] (given in the
  /// portrait capture) is turned by how the phone was held.
  Future<AutoEditsResult> ingest(
    String sourcePath, {
    required String previewOut,
    double? snapAspectRatio,
    Quad? guide,
    double? outputAspect,
    FilterType filter = FilterType.auto,
    CaptureMeta? capture,
  });

  /// Enhance preview (filter only; sliders are applied live in the UI).
  /// [workPath] caches the cropped page at preview size between calls.
  Future<String> renderLook(
    String originalPath,
    PageEdits edits, {
    required String workPath,
    required String outputPath,
    CancelToken? cancel,
  });

  /// Max file size (feature 2): finds the best [ShrinkStep] at which the
  /// [bases] (2000 px page renders) plus [overheadBytes] fit [targetBytes],
  /// and on a fit writes each page at that step to [outputs]. Background lane.
  Future<ShrinkOutcome> shrinkPages(
    List<String> bases, {
    required int targetBytes,
    required int overheadBytes,
    required bool grayscale,
    required List<String> outputs,
  });

  /// A passport photo (feature 5) at its print size and [dpi]. Background.
  Future<String> renderPhoto(
    String originalPath,
    PageEdits edits, {
    required double widthMm,
    required double heightMm,
    required int dpi,
    required String outputPath,
  });

  /// Turns a fresh camera photo upright in place (P0-1: EXIF, then what
  /// [capture] says; null for imports). Interactive lane. Returns the
  /// `[orient]` line.
  Future<String> normalizeCapture(String path, CaptureMeta? capture);

  /// Scan from paper (feature 4): a photo of a signature → transparent PNG
  /// at [outputPath], made upright from [capture] first. Throws when no
  /// ink is found.
  Future<String> signatureFromPhoto(String photo, {required String outputPath, CaptureMeta? capture});

  /// All six filter thumbnails for one page in one job (160 px, P0-4).
  Future<void> renderFilterStrip(
    String originalPath,
    PageEdits edits, {
    required Map<FilterType, String> outputs,
  });

  /// The fast placeholder (P0-4): crop + rotate only, 600 px, no filter,
  /// interactive lane. Never the uncropped photo.
  Future<String> renderQuick(
    String originalPath,
    PageEdits edits, {
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
    JobPriority priority,
  });

  /// Full-resolution crop + rotate → gray → mild contrast → denoise, for text
  /// recognition. Ignores the filter and sliders in [edits].
  Future<String> renderForOcr(
    String originalPath,
    PageEdits edits, {
    required String outputPath,
  });

  /// One card side for print at real size and [dpi] (never above native),
  /// encoded once to [outputPath] (P1-9).
  Future<String> renderCard(
    String originalPath,
    PageEdits edits, {
    required double widthMm,
    required double heightMm,
    required int dpi,
    required String outputPath,
  });

  /// Candidate lines and corners for magnetic crop handles (P1-3), from the
  /// editor's base preview.
  Future<SnapCandidates> snapCandidates(
    String previewPath, {
    double? aspectHint,
  });

  /// Pixel size of an image without decoding it fully.
  Future<({int width, int height})> imageSize(String imagePath);
}

class AutoEditsResult {
  const AutoEditsResult({
    required this.edits,
    required this.detected,
    this.sharpness,
    this.cardSharpness,
    this.brightness,
    this.width,
    this.height,
    this.candidates = const [],
    this.orientation,
  });

  final PageEdits edits;

  /// The `[orient]` line (P0-1), for the dev-build label on Adjust edges.
  final String? orientation;

  /// False when the crop is a fallback and the user should be told to drag
  /// the corners.
  final bool detected;

  /// Capture checks (see `CaptureChecks`). null when not measured.
  final double? sharpness;

  /// ID / passport: sharpness of the warped card itself (P0-2).
  final double? cardSharpness;
  final double? brightness;

  /// Original photo size in pixels (upright).
  final int? width;
  final int? height;

  /// Top detection candidates, best first (magnetic corners).
  final List<Quad> candidates;
}
