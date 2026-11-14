import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/utils/exif_orientation.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/editor/domain/snap_guide.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// OpenCV implementation. Every call is queued on the shared [IsolateRunner]
/// so the UI thread never blocks and two renders never overlap.
@LazySingleton(as: ImageProcessor)
class OpenCvImageProcessor implements ImageProcessor {
  OpenCvImageProcessor(this._runner);

  final IsolateRunner _runner;

  @override
  Future<Quad?> detectEdges(String imagePath, {double? snapAspectRatio}) async {
    final r = await _runner.run(
      detectInIsolate,
      DetectMsg(imagePath, snapAspectRatio),
      debugLabel: 'detectEdges',
      priority: JobPriority.interactive,
    );
    debugPrint('[edges] ${r.log}');
    return r.quad;
  }

  @override
  Future<AutoEditsResult> ingest(
    String sourcePath, {
    required String previewOut,
    double? snapAspectRatio,
    Quad? guide,
    double? outputAspect,
    FilterType filter = FilterType.auto,
    CaptureMeta? capture,
  }) async {
    // The guide was mapped into the portrait capture; turn it the way the
    // phone was held (the sensor part brings the raw pixels to that frame).
    if (capture != null) {
      guide = guide?.rotatedQuarterTurns(capture.frontCamera ? -capture.deviceTurns : capture.deviceTurns);
    }
    final r = await _runner.run(
      ingestInIsolate,
      IngestMsg(sourcePath, previewOut, snapAspectRatio, guide, capture),
      debugLabel: 'ingest',
    );
    debugPrint(r.orientation);
    debugPrint('[ingest] ${r.log}');
    return AutoEditsResult(
      edits: PageEdits(
        crop: r.quad ?? pipe.fallbackQuad(guide: guide),
        filter: filter,
        outputAspect: outputAspect,
      ),
      detected: r.quad != null,
      orientation: r.orientation,
      sharpness: r.sharpness,
      cardSharpness: r.cardSharpness,
      brightness: r.brightness,
      width: r.width,
      height: r.height,
      candidates: r.ranked,
    );
  }

  @override
  Future<String> renderLook(
    String originalPath,
    PageEdits edits, {
    required String workPath,
    required String outputPath,
    CancelToken? cancel,
  }) {
    return _runner.run(
      lookInIsolate,
      LookMsg(originalPath, edits, workPath, outputPath),
      debugLabel: 'look',
      priority: JobPriority.interactive,
      cancel: cancel,
    );
  }

  @override
  Future<ShrinkOutcome> shrinkPages(
    List<String> bases, {
    required int targetBytes,
    required int overheadBytes,
    required bool grayscale,
    required List<String> outputs,
    int minEdge = ShrinkToFit.minEdge,
  }) {
    return _runner.run(
      shrinkInIsolate,
      ShrinkMsg(bases, targetBytes, overheadBytes, grayscale, outputs, minEdge),
      debugLabel: 'shrink',
    );
  }

  @override
  Future<String> renderPhoto(
    String originalPath,
    PageEdits edits, {
    required double widthMm,
    required double heightMm,
    required int dpi,
    required String outputPath,
  }) {
    return _runner.run(
      photoInIsolate,
      PhotoMsg(originalPath, edits, widthMm, heightMm, dpi, outputPath),
      debugLabel: 'photo',
    );
  }

  @override
  Future<String> normalizeCapture(String path, CaptureMeta? capture) async {
    final report = await _runner.run(
      normalizeInIsolate,
      (path, capture),
      debugLabel: 'normalize',
      priority: JobPriority.interactive,
    );
    debugPrint(report);
    return report;
  }

  @override
  Future<String> resizeExact(String src, int width, int height, {required String outputPath, int jpegQuality = 92}) =>
      _runner.run(exactInIsolate, (src, width, height, outputPath, jpegQuality), debugLabel: 'exactSize');

  @override
  Future<void> writeGrayImage(Uint8List data, int width, int height, String outputPath) =>
      _runner.run(grayInIsolate, (data, width, height, outputPath), debugLabel: 'mask', priority: JobPriority.interactive);

  @override
  Future<String> previewWithBackground(
    String photoPath,
    String? maskPath,
    PhotoBackground background, {
    required String outputPath,
    PhotoEnhance enhance = PhotoEnhance.off,
  }) => _runner.run(
    backgroundPreviewInIsolate,
    (photoPath, maskPath, background, enhance, outputPath),
    debugLabel: 'background',
    priority: JobPriority.interactive,
  );

  @override
  Future<({int width, int height})> renderRegion(
    String photoPath,
    FracRect region, {
    required int longEdge,
    required String outputPath,
  }) async {
    final (w, h) = await _runner.run(
      regionInIsolate,
      (photoPath, region, longEdge, outputPath),
      debugLabel: 'region',
      priority: JobPriority.interactive,
    );
    return (width: w, height: h);
  }

  @override
  Future<void> composeMask(
    String? base,
    Uint8List data,
    int width,
    int height,
    FracRect region,
    String outputPath,
  ) => _runner.run(
    composeMaskInIsolate,
    (base, data, width, height, region, outputPath),
    debugLabel: 'mask',
    priority: JobPriority.interactive,
  );

  @override
  Future<String> signatureFromPhoto(String photo, {required String outputPath, CaptureMeta? capture}) {
    return _runner.run(
      signatureInIsolate,
      SignatureMsg(photo, outputPath, capture),
      debugLabel: 'signature',
      priority: JobPriority.interactive,
    );
  }

  @override
  Future<void> renderFilterStrip(
    String originalPath,
    PageEdits edits, {
    required Map<FilterType, String> outputs,
  }) {
    return _runner.run(
      stripInIsolate,
      StripMsg(originalPath, edits, outputs),
      debugLabel: 'strip',
      priority: JobPriority.interactive,
    );
  }

  @override
  Future<String> renderQuick(
    String originalPath,
    PageEdits edits, {
    required String outputPath,
  }) {
    return _runner.run(
      renderInIsolate,
      RenderMsg(
        originalPath,
        edits.copyWith(filter: FilterType.original, brightness: 0, contrast: 0),
        600,
        outputPath,
        80,
      ),
      debugLabel: 'quick',
      priority: JobPriority.interactive,
    );
  }

  @override
  Future<void> renderPageCaches(
    String originalPath,
    PageEdits edits, {
    required String processedOut,
    required String thumbOut,
  }) {
    return _runner.run(
      cachesInIsolate,
      CachesMsg(originalPath, edits, processedOut, thumbOut),
      debugLabel: 'caches',
    );
  }

  @override
  Future<String> render(
    String originalPath,
    PageEdits edits, {
    required RenderSize size,
    required String outputPath,
    int jpegQuality = Limits.cacheJpegQuality,
    JobPriority priority = JobPriority.background,
  }) {
    return _runner.run(
      renderInIsolate,
      RenderMsg(originalPath, edits, size.longEdge, outputPath, jpegQuality),
      debugLabel: 'render',
      priority: priority,
    );
  }

  @override
  Future<String> renderForOcr(
    String originalPath,
    PageEdits edits, {
    required String outputPath,
  }) {
    return _runner.run(
      renderOcrInIsolate,
      RenderMsg(originalPath, edits, null, outputPath, 92),
      debugLabel: 'renderOcr',
    );
  }

  @override
  Future<String> renderCard(
    String originalPath,
    PageEdits edits, {
    required double widthMm,
    required double heightMm,
    required int dpi,
    required String outputPath,
  }) {
    return _runner.run(
      cardInIsolate,
      CardMsg(originalPath, edits, widthMm, heightMm, dpi, outputPath),
      debugLabel: 'card',
    );
  }

  @override
  Future<SnapCandidates> snapCandidates(
    String previewPath, {
    double? aspectHint,
  }) async {
    final r = await _runner.run(
      snapInIsolate,
      DetectMsg(previewPath, aspectHint),
      debugLabel: 'snap',
    );
    return SnapCandidates(lines: r.lines, corners: r.corners);
  }

  @override
  Future<({int width, int height})> imageSize(String imagePath) {
    return _runner.run(sizeInIsolate, imagePath, debugLabel: 'imageSize');
  }
}

// ---------------------------------------------------------------------------
// Isolate entry points (top-level, single argument). Public so tests can run
// them directly on the host.
// ---------------------------------------------------------------------------

class DetectMsg {
  const DetectMsg(this.path, this.snapAspect);
  final String path;
  final double? snapAspect;
}

class DetectResult {
  const DetectResult(this.quad, this.log);
  final Quad? quad;
  final String log;
}

class RenderMsg {
  const RenderMsg(this.path, this.edits, this.longEdge, this.out, this.quality);
  final String path;
  final PageEdits edits;
  final int? longEdge;
  final String out;
  final int quality;
}

class IngestMsg {
  const IngestMsg(
    this.src,
    this.previewOut,
    this.snapAspect,
    this.guide, [
    this.capture,
  ]);
  final String src;
  final String previewOut;
  final double? snapAspect;
  final Quad? guide;
  final CaptureMeta? capture;
}

class IngestResult {
  const IngestResult({
    required this.quad,
    required this.ranked,
    required this.sharpness,
    required this.brightness,
    required this.width,
    required this.height,
    required this.log,
    required this.orientation,
    this.cardSharpness,
  });
  final String orientation;
  final Quad? quad;
  final List<Quad> ranked;
  final double sharpness;
  final double? cardSharpness;
  final double brightness;
  final int width;
  final int height;
  final String log;
}

class LookMsg {
  const LookMsg(this.path, this.edits, this.workPath, this.out);
  final String path;
  final PageEdits edits;
  final String workPath;
  final String out;
}

class CachesMsg {
  const CachesMsg(this.path, this.edits, this.processedOut, this.thumbOut);
  final String path;
  final PageEdits edits;
  final String processedOut;
  final String thumbOut;
}

IngestResult ingestInIsolate(IngestMsg m) {
  final sw = Stopwatch()..start();
  final g = m.guide;
  final r = pipe.ingest(
    src: m.src,
    previewOut: m.previewOut,
    previewLongEdge: RenderPx.previewLongEdge,
    aspectHint: m.snapAspect,
    capture: m.capture,
    searchArea: g == null
        ? null
        : (
            left: [g.tl.x, g.bl.x].reduce(math.min),
            top: [g.tl.y, g.tr.y].reduce(math.min),
            right: [g.tr.x, g.br.x].reduce(math.max),
            bottom: [g.bl.y, g.br.y].reduce(math.max),
          ),
  );
  final mb = File(m.src).lengthSync() / (1024 * 1024);
  return IngestResult(
    orientation: r.orientation,
    quad: r.detection.quad,
    ranked: r.detection.ranked,
    sharpness: r.sharpness,
    cardSharpness: r.cardSharpness,
    brightness: r.brightness,
    width: r.width,
    height: r.height,
    log:
        '${r.width}×${r.height} (${(r.width * r.height / 1e6).toStringAsFixed(1)} MP, '
        '${mb.toStringAsFixed(1)} MB) decode 1/${r.decodeScale}; ${r.detection}; '
        'sharpness ${r.sharpness.toStringAsFixed(0)}${r.cardSharpness == null ? '' : ' card ${r.cardSharpness!.toStringAsFixed(0)}'} brightness ${r.brightness.toStringAsFixed(0)}; '
        'total ${sw.elapsedMilliseconds} ms',
  );
}

String lookInIsolate(LookMsg m) {
  final out = pipe.renderLook(
    m.path,
    m.edits,
    workPath: m.workPath,
    previewLongEdge: RenderPx.previewLongEdge,
  );
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(out, m.out, quality: 85);
    return m.out;
  } finally {
    out.dispose();
  }
}

void cachesInIsolate(CachesMsg m) {
  pipe.renderPageCaches(
    m.path,
    m.edits,
    processedOut: m.processedOut,
    thumbOut: m.thumbOut,
    previewLongEdge: RenderPx.previewLongEdge,
    thumbLongEdge: RenderPx.thumbLongEdge,
  );
}

DetectResult detectInIsolate(DetectMsg m) {
  final img = pipe.readUprightAtMost(m.path, RenderPx.previewLongEdge * 2);
  try {
    final report = pipe.detectDocument(img, aspectHint: m.snapAspect);
    return DetectResult(report.quad, report.toString());
  } finally {
    img.dispose();
  }
}

({List<(Pt, Pt)> lines, List<Pt> corners}) snapInIsolate(DetectMsg m) {
  final img = pipe.readUpright(m.path);
  try {
    return pipe.snapCandidates(img, aspectHint: m.snapAspect);
  } finally {
    img.dispose();
  }
}

class CardMsg {
  const CardMsg(
    this.path,
    this.edits,
    this.widthMm,
    this.heightMm,
    this.dpi,
    this.out,
  );
  final String path;
  final PageEdits edits;
  final double widthMm;
  final double heightMm;
  final int dpi;
  final String out;
}

String cardInIsolate(CardMsg m) {
  final card = pipe.renderCard(
    m.path,
    m.edits,
    widthMm: m.widthMm,
    heightMm: m.heightMm,
    dpi: m.dpi,
  );
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(card, m.out, quality: 95);
    return m.out;
  } finally {
    card.dispose();
  }
}

/// Renders an export. If the full-resolution render fails (out of memory on
/// a low-end phone), retries at A4 300 DPI (3508 px) and then 2000 px
/// instead of failing the export (P0-C).
class PhotoMsg {
  const PhotoMsg(this.path, this.edits, this.widthMm, this.heightMm, this.dpi, this.out);
  final String path;
  final PageEdits edits;
  final double widthMm;
  final double heightMm;
  final int dpi;
  final String out;
}

String photoInIsolate(PhotoMsg m) {
  final img = pipe.renderSized(m.path, m.edits, widthMm: m.widthMm, heightMm: m.heightMm, dpi: m.dpi);
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(img, m.out, quality: 95);
    return m.out;
  } finally {
    img.dispose();
  }
}

String normalizeInIsolate((String, CaptureMeta?) m) => pipe.normalizeCapture(m.$1, m.$2);

String exactInIsolate((String, int, int, String, int) m) {
  final img = cv.imread(m.$1);
  final out = pipe.coverResize(img, m.$2, m.$3);
  img.dispose();
  try {
    File(m.$4).parent.createSync(recursive: true);
    pipe.writeJpeg(out, m.$4, quality: m.$5);
    return m.$4;
  } finally {
    out.dispose();
  }
}

void grayInIsolate((Uint8List, int, int, String) m) => pipe.writeGray(m.$1, m.$2, m.$3, m.$4);

String backgroundPreviewInIsolate(
  (String, String?, PhotoBackground, PhotoEnhance, String) m,
) {
  final img = pipe.readUprightAtMost(m.$1, RenderPx.previewLongEdge);
  final small = pipe.fitLongEdge(img, RenderPx.previewLongEdge);
  pipe.disposeUnless(img, small);
  final path = m.$2;
  final read = path == null
      ? null
      : cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
  final mask = read == null || read.isEmpty ? null : read;
  try {
    final out = pipe.finishPhoto(
      small,
      mask,
      color: pipe.photoBackgroundColor(m.$3),
      enhance: m.$4,
    );
    File(m.$5).parent.createSync(recursive: true);
    pipe.writeJpeg(out, m.$5, quality: 88);
    if (!identical(out, small)) out.dispose();
    return m.$5;
  } finally {
    small.dispose();
    read?.dispose();
  }
}

(int, int) regionInIsolate((String, FracRect, int, String) m) =>
    pipe.writeRegion(m.$1, m.$2, m.$3, m.$4);

void composeMaskInIsolate((String?, Uint8List, int, int, FracRect, String) m) =>
    pipe.composeMask(m.$1, m.$2, m.$3, m.$4, m.$5, m.$6);

class SignatureMsg {
  const SignatureMsg(this.photo, this.out, this.capture);
  final String photo;
  final String out;
  final CaptureMeta? capture;
}

String signatureInIsolate(SignatureMsg m) {
  pipe.normalizeCapture(m.photo, m.capture);
  pipe.signatureFromPhoto(m.photo, m.out);
  return m.out;
}

class ShrinkMsg {
  const ShrinkMsg(this.bases, this.target, this.overhead, this.grayscale, this.outputs, [this.minEdge = ShrinkToFit.minEdge]);
  final List<String> bases;
  final int target;
  final int overhead;
  final bool grayscale;
  final List<String> outputs;
  final int minEdge;
}

/// Decodes each page once, keeps one resized copy per long edge, and
/// measures in memory: nothing touches the disk until the search is done.
ShrinkOutcome shrinkInIsolate(ShrinkMsg m) {
  final sources = [for (final b in m.bases) cv.imread(b)];
  final sized = <int, List<cv.Mat>>{};
  List<cv.Mat> at(int edge) => sized.putIfAbsent(edge, () {
        return [
          for (final src in sources)
            () {
              final long = math.max(src.cols, src.rows);
              final s = math.min(1.0, edge / long);
              final r = s < 1
                  ? cv.resize(src, ((src.cols * s).round(), (src.rows * s).round()), interpolation: cv.INTER_AREA)
                  : src.clone();
              if (!m.grayscale) return r;
              final g = cv.cvtColor(r, cv.COLOR_BGR2GRAY);
              r.dispose();
              return g;
            }(),
        ];
      });
  int jpegBytes(cv.Mat img, int quality) {
    final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]);
    final (ok, bytes) = cv.imencode('.jpg', img, params: params);
    params.dispose();
    if (!ok) throw StateError('jpeg encode failed');
    return bytes.length;
  }

  try {
    final outcome = ShrinkToFit.search(
      m.target,
      (step) => m.overhead + at(step.longEdge).fold(0, (sum, img) => sum + jpegBytes(img, step.quality)),
      grayscale: m.grayscale,
      min: m.minEdge,
    );
    if (outcome is ShrinkFits) {
      for (final (i, img) in at(outcome.step.longEdge).indexed) {
        File(m.outputs[i]).parent.createSync(recursive: true);
        pipe.writeJpeg(img, m.outputs[i], quality: outcome.step.quality);
      }
    }
    return outcome;
  } finally {
    for (final mats in sized.values) {
      for (final mat in mats) {
        mat.dispose();
      }
    }
    for (final s in sources) {
      s.dispose();
    }
  }
}

class StripMsg {
  const StripMsg(this.path, this.edits, this.outputs);
  final String path;
  final PageEdits edits;
  final Map<FilterType, String> outputs;
}

void stripInIsolate(StripMsg m) {
  final img = pipe.readUprightAtMost(m.path, 640);
  final small = pipe.cropAndRotate(img, m.edits, maxLongEdge: 160);
  pipe.disposeUnless(img, small);
  try {
    for (final MapEntry(key: f, value: out) in m.outputs.entries) {
      final r = pipe.applyFilter(small, f);
      File(out).parent.createSync(recursive: true);
      pipe.writeJpeg(r, out, quality: 80);
      r.dispose();
    }
  } finally {
    small.dispose();
  }
}

String renderInIsolate(RenderMsg m) {
  final sizes = <int?>[
    m.longEdge,
    if (m.longEdge == null || m.longEdge! > 3508) 3508,
    if (m.longEdge == null || m.longEdge! > 2000) 2000,
  ];
  Object? lastError;
  for (final size in sizes) {
    try {
      return _renderOnce(m, size);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError('render failed: $lastError');
}

String _renderOnce(RenderMsg m, int? longEdge) {
  final out = pipe.renderEdits(m.path, m.edits, maxLongEdge: longEdge);
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(out, m.out, quality: m.quality);
    return m.out;
  } finally {
    out.dispose();
  }
}

String renderOcrInIsolate(RenderMsg m) {
  final out = pipe.renderForOcr(m.path, m.edits);
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(out, m.out, quality: m.quality);
    return m.out;
  } finally {
    out.dispose();
  }
}

({int width, int height}) sizeInIsolate(String path) {
  final img = cv.imread(
    path,
    flags: cv.IMREAD_REDUCED_GRAYSCALE_8 | cv.IMREAD_IGNORE_ORIENTATION,
  );
  try {
    final w = math.max(1, img.cols * 8);
    final h = math.max(1, img.rows * 8);
    return orientationSwapsAxes(readJpegOrientation(path))
        ? (width: h, height: w)
        : (width: w, height: h);
  } finally {
    img.dispose();
  }
}
