import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
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
    );
    debugPrint('[edges] ${r.log}');
    return r.quad;
  }

  @override
  Future<AutoEditsResult> autoEdits(
    String imagePath, {
    double? snapAspectRatio,
    Quad? fallback,
    FilterType filter = FilterType.auto,
  }) async {
    final r = await _runner.run(
      detectInIsolate,
      DetectMsg(imagePath, snapAspectRatio),
      debugLabel: 'autoEdits',
    );
    debugPrint('[edges] ${r.log}');
    final crop = r.quad ?? fallback ?? Quad.full(inset: 0.05);
    return AutoEditsResult(
      edits: PageEdits(crop: crop, filter: filter),
      detected: r.quad != null,
    );
  }

  @override
  Future<String> render(
    String originalPath,
    PageEdits edits, {
    required RenderSize size,
    required String outputPath,
    int jpegQuality = Limits.cacheJpegQuality,
  }) {
    return _runner.run(
      renderInIsolate,
      RenderMsg(originalPath, edits, size.longEdge, outputPath, jpegQuality),
      debugLabel: 'render',
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
  Future<String> normalizeOrientation(String imagePath, {String? outputPath}) {
    return _runner.run(
      normalizeInIsolate,
      NormalizeMsg(imagePath, outputPath ?? imagePath),
      debugLabel: 'normalize',
    );
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

class NormalizeMsg {
  const NormalizeMsg(this.path, this.out);
  final String path;
  final String out;
}

/// Max long edge kept for stored originals (48 MP phones → 4000 px).
const int kMaxOriginalLongEdge = 4000;

DetectResult detectInIsolate(DetectMsg m) {
  final img = pipe.readUpright(m.path);
  try {
    final report = pipe.detectDocument(img, aspectHint: m.snapAspect);
    var quad = report.quad;
    if (quad != null && m.snapAspect != null) {
      quad = pipe
          .snapQuadToAspect(quad, m.snapAspect!, imageAspect: img.cols / img.rows)
          .clamp01();
    }
    return DetectResult(quad, report.toString());
  } finally {
    img.dispose();
  }
}

String renderInIsolate(RenderMsg m) {
  final out = pipe.renderEdits(m.path, m.edits, maxLongEdge: m.longEdge);
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

String normalizeInIsolate(NormalizeMsg m) {
  // imread applies EXIF orientation; writing back produces an upright JPEG
  // with no orientation tag, so every later step can ignore EXIF.
  final img = pipe.readUpright(m.path);
  // Cap very large captures to keep later steps fast while staying far
  // above export needs. `fitLongEdge` returns `img` itself when no resize
  // is needed, so dispose exactly once.
  final capped = pipe.fitLongEdge(img, kMaxOriginalLongEdge);
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(capped, m.out, quality: 95);
    return m.out;
  } finally {
    pipe.disposeUnless(capped, img);
    img.dispose();
  }
}

({int width, int height}) sizeInIsolate(String path) {
  final img = cv.imread(path, flags: cv.IMREAD_REDUCED_GRAYSCALE_8);
  try {
    return (width: math.max(1, img.cols * 8), height: math.max(1, img.rows * 8));
  } finally {
    img.dispose();
  }
}
