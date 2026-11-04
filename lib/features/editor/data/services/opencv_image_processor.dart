import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// OpenCV implementation. Every call is queued on the shared [IsolateRunner]
/// so the UI thread never blocks and two renders never overlap.
@LazySingleton(as: ImageProcessor)
class OpenCvImageProcessor implements ImageProcessor {
  OpenCvImageProcessor(this._runner);

  final IsolateRunner _runner;

  @override
  Future<Quad?> detectEdges(String imagePath, {double? snapAspectRatio}) {
    return _runner.run(
      _detect,
      _DetectMsg(imagePath, snapAspectRatio),
      debugLabel: 'detectEdges',
    );
  }

  @override
  Future<PageEdits> autoEdits(String imagePath, {double? snapAspectRatio}) {
    return _runner.run(
      _auto,
      _DetectMsg(imagePath, snapAspectRatio),
      debugLabel: 'autoEdits',
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
      _render,
      _RenderMsg(originalPath, edits, size.longEdge, outputPath, jpegQuality),
      debugLabel: 'render',
    );
  }

  @override
  Future<String> normalizeOrientation(String imagePath, {String? outputPath}) {
    return _runner.run(
      _normalize,
      _NormalizeMsg(imagePath, outputPath ?? imagePath),
      debugLabel: 'normalize',
    );
  }

  @override
  Future<({int width, int height})> imageSize(String imagePath) {
    return _runner.run(_size, imagePath, debugLabel: 'imageSize');
  }
}

// ---------------------------------------------------------------------------
// Isolate entry points (top-level, single argument)
// ---------------------------------------------------------------------------

class _DetectMsg {
  const _DetectMsg(this.path, this.snapAspect);
  final String path;
  final double? snapAspect;
}

class _RenderMsg {
  const _RenderMsg(this.path, this.edits, this.longEdge, this.out, this.quality);
  final String path;
  final PageEdits edits;
  final int? longEdge;
  final String out;
  final int quality;
}

class _NormalizeMsg {
  const _NormalizeMsg(this.path, this.out);
  final String path;
  final String out;
}

Quad? _detect(_DetectMsg m) {
  final img = pipe.readUpright(m.path);
  try {
    return pipe.detectDocumentQuad(img, snapAspectRatio: m.snapAspect);
  } finally {
    img.dispose();
  }
}

PageEdits _auto(_DetectMsg m) {
  final img = pipe.readUpright(m.path);
  try {
    final quad = pipe.detectDocumentQuad(img, snapAspectRatio: m.snapAspect) ??
        Quad.full(inset: 0.02);
    return PageEdits(crop: quad);
  } finally {
    img.dispose();
  }
}

String _render(_RenderMsg m) {
  final out = pipe.renderEdits(m.path, m.edits, maxLongEdge: m.longEdge);
  try {
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(out, m.out, quality: m.quality);
    return m.out;
  } finally {
    out.dispose();
  }
}

String _normalize(_NormalizeMsg m) {
  // imread applies EXIF orientation; writing back produces an upright JPEG
  // with no orientation tag, so every later step can ignore EXIF.
  final img = pipe.readUpright(m.path);
  try {
    // Cap very large captures (48 MP phones) to keep later steps fast while
    // staying far above export needs.
    final capped = pipe.fitLongEdge(img, 4000);
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(capped, m.out, quality: 95);
    if (!identical(capped, img)) capped.dispose();
    return m.out;
  } finally {
    img.dispose();
  }
}

({int width, int height}) _size(String path) {
  final img = cv.imread(path, flags: cv.IMREAD_REDUCED_GRAYSCALE_8);
  try {
    // Reduced read gives 1/8 size; scale back. Good enough for aspect ratios.
    return (width: math.max(1, img.cols * 8), height: math.max(1, img.rows * 8));
  } finally {
    img.dispose();
  }
}
