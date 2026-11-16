// Pure OpenCV steps for the image pipeline. Each function is small and
// synchronous so it can be unit-tested on sample photos and run inside an
// isolate by `OpenCvImageProcessor`.
//
// Ownership rule: a function never disposes a Mat it was given. It returns a
// new Mat the caller owns, or (where documented) the same Mat it received.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flash_dox/core/utils/exif_orientation.dart';
import 'package:flash_dox/core/utils/step_timer.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:opencv_dart/opencv.dart' as cv;

// ---------------------------------------------------------------------------
// Loading / sizing
// ---------------------------------------------------------------------------

/// Reads an image upright (round 4, P0-1).
///
/// OpenCV is always told to IGNORE the EXIF orientation, and the tag is
/// applied here instead, so a photo can never come back sideways or be
/// rotated twice whatever the OpenCV build does. Ingest bakes the tag into
/// new originals, so for them this is a plain decode; legacy files that
/// still carry a tag are handled the same way.
cv.Mat readUpright(String path, {int flags = cv.IMREAD_COLOR}) {
  final m = cv.imread(path, flags: flags | cv.IMREAD_IGNORE_ORIENTATION);
  if (m.isEmpty) {
    m.dispose();
    throw StateError('Could not decode $path');
  }
  final o = readJpegOrientation(path);
  final out = applyExifOrientation(m, o);
  if (!identical(out, m)) m.dispose();
  return out;
}

/// The EXIF orientation transform, exactly as OpenCV's own
/// `ApplyExifOrientation`. Returns [m] itself for orientation 1.
cv.Mat applyExifOrientation(cv.Mat m, int orientation) {
  switch (orientation) {
    case 2:
      return cv.flip(m, 1);
    case 3:
      return cv.flip(m, -1);
    case 4:
      return cv.flip(m, 0);
    case 5:
      return cv.transpose(m);
    case 6:
    case 7:
    case 8:
      final t = cv.transpose(m);
      final out = cv.flip(
        t,
        orientation == 6
            ? 1
            : orientation == 7
            ? -1
            : 0,
      );
      t.dispose();
      return out;
    default:
      return m;
  }
}

/// Makes a photo upright once, in place (round 5, P0-1): the EXIF tag, then
/// the rotation [captureRotation] works out from what the camera knew
/// ([meta]; null for imports, which get the tag only). The result is an
/// upright JPEG (q95) with no orientation tag; when nothing needs turning
/// the file is left byte-for-byte as it is. Returns the `[orient]` line.
///
/// With [maxLongEdge] (round 6, P0-3: scans keep 3000 px, still ~300 DPI
/// on A4) a larger photo is also shrunk, in the same single re-encode, at
/// [shrunkJpegQuality]: a 16 MP / 4 MB camera file becomes ~1.3 MB.
String normalizeCapture(String path, CaptureMeta? meta, {int? maxLongEdge}) {
  final o = readJpegOrientation(path);
  var size = jpegSize(path);
  if (size == null) {
    final probe = cv.imread(
      path,
      flags: cv.IMREAD_REDUCED_GRAYSCALE_8 | cv.IMREAD_IGNORE_ORIENTATION,
    );
    size = (width: probe.cols, height: probe.rows);
    probe.dispose();
  }
  final rot = captureRotation(
    exif: o,
    width: size.width,
    height: size.height,
    meta: meta,
  );
  final long = math.max(size.width, size.height);
  final shrink = maxLongEdge != null && long > maxLongEdge;
  final report =
      '[orient] exif=$o ${meta ?? 'import'} pixels=${size.width}x${size.height} '
      'final=${rot.turns * 90}°${rot.mirror ? ' mirrored' : ''}'
      '${shrink ? ' shrunk to $maxLongEdge px' : ''}';
  if (o <= 1 && rot.turns == 0 && !rot.mirror && !shrink) return report;
  // A 48 MP+ photo is decoded at half size straight from the JPEG: the
  // full decode alone would be ~150 MB.
  final half = shrink && long ~/ 2 >= maxLongEdge;
  var raw = cv.imread(
    path,
    flags: (half ? cv.IMREAD_REDUCED_COLOR_2 : cv.IMREAD_COLOR) | cv.IMREAD_IGNORE_ORIENTATION,
  );
  if (raw.isEmpty) {
    raw.dispose();
    throw StateError('Could not decode $path');
  }
  if (shrink) {
    final small = fitLongEdge(raw, maxLongEdge);
    if (!identical(small, raw)) raw.dispose();
    raw = small;
  }
  final upright = applyExifOrientation(raw, o);
  if (!identical(upright, raw)) raw.dispose();
  var turned = rotateQuarterTurns(upright, rot.turns);
  if (!identical(turned, upright)) upright.dispose();
  if (rot.mirror) {
    final flipped = cv.flip(turned, 1);
    turned.dispose();
    turned = flipped;
  }
  try {
    final tmp = '$path.baking.jpg';
    writeJpeg(turned, tmp, quality: shrink ? shrunkJpegQuality : 95);
    File(tmp).renameSync(path);
    return report;
  } finally {
    turned.dispose();
  }
}

/// Long edge scans are kept at, and their JPEG quality (round 6, P0-3).
const int scanMaxLongEdge = 3000;
const int shrunkJpegQuality = 90;

/// Imports: the EXIF tag only.
void bakeOrientation(String path) => normalizeCapture(path, null);

/// Decodes at 1/2 or 1/4 scale straight from the JPEG when the photo is far
/// larger than [targetLongEdge] (48–200 MP sensors). Halves or quarters the
/// decode time and peak memory; the result is still ≥ [targetLongEdge].
cv.Mat readUprightAtMost(String path, int targetLongEdge) {
  final size = jpegSize(path);
  var flags = cv.IMREAD_COLOR;
  if (size != null) {
    final long = math.max(size.width, size.height);
    if (long >= targetLongEdge * 4) {
      flags = cv.IMREAD_REDUCED_COLOR_4;
    } else if (long >= targetLongEdge * 2) {
      flags = cv.IMREAD_REDUCED_COLOR_2;
    }
  }
  return readUpright(path, flags: flags);
}

/// Previews only: decodes at 1/2 or 1/4 scale when the CROPPED part of the
/// photo still has ≥ 1.25× [outLongEdge] pixels afterwards. A 12 MP page at
/// 1200 px decodes at 1/2 (a quarter of the pixels), the 600 px placeholder
/// at 1/4. Exports keep the full decode (their output must not change).
cv.Mat readUprightForCrop(String path, Quad? crop, int outLongEdge) {
  final size = jpegSize(path);
  var flags = cv.IMREAD_COLOR;
  if (size != null) {
    // Upright size: EXIF orientations 5–8 swap width and height.
    final swap = readJpegOrientation(path) >= 5;
    final w = swap ? size.height : size.width;
    final h = swap ? size.width : size.height;
    final b = (crop ?? Quad.full()).bounds();
    final cropLong = math.max((b.right - b.left) * w, (b.bottom - b.top) * h);
    final need = outLongEdge * 1.25;
    if (cropLong >= need * 4) {
      flags = cv.IMREAD_REDUCED_COLOR_4;
    } else if (cropLong >= need * 2) {
      flags = cv.IMREAD_REDUCED_COLOR_2;
    }
  }
  return readUpright(path, flags: flags);
}

/// Pixel size from a JPEG's SOF header without decoding, or null if the file
/// isn't a JPEG or the header can't be found in the first 1 MB.
({int width, int height})? jpegSize(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    final bytes = f.readSync(1 << 20);
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      // Standalone markers have no length.
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
        i += 2;
        continue;
      }
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return (width: w, height: h);
      }
      if (marker == 0xDA) return null; // start of scan, no SOF seen
      i += 2 + len;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    f?.closeSync();
  }
}

/// Returns a copy downscaled so the long edge is at most [longEdge], using
/// area averaging. Returns [src] itself (NOT a copy) when it is already small
/// enough; never enlarges and never disposes [src].
cv.Mat fitLongEdge(cv.Mat src, int longEdge) {
  final long = math.max(src.cols, src.rows);
  if (long <= longEdge) return src;
  final k = longEdge / long;
  return cv.resize(
    src,
    (math.max(1, (src.cols * k).round()), math.max(1, (src.rows * k).round())),
    interpolation: cv.INTER_AREA,
  );
}

/// Disposes [m] unless it is the very same object as [keep].
void disposeUnless(cv.Mat m, cv.Mat keep) {
  if (!identical(m, keep)) m.dispose();
}

// ---------------------------------------------------------------------------
// Edge detection — port of `detect_document()` in tool/reference/
// flashdox_reference.py (owner's reference). Keep the two in step.
// ---------------------------------------------------------------------------

const int kDetectLongEdge = 800;
const double kMinAreaFrac = 0.05;

class DetectionReport {
  const DetectionReport({
    required this.quad,
    required this.score,
    required this.elapsed,
    required this.strategy,
    required this.candidates,
    this.ranked = const [],
  });

  /// Normalised corners TL, TR, BR, BL, or null when nothing convincing.
  final Quad? quad;
  final double score;
  final Duration elapsed;

  /// Map that produced the winner: `edges`, `bright`, `lowsat`, or `none`.
  final String strategy;
  final int candidates;

  /// Up to five best candidates, best first (used for magnetic corners).
  final List<Quad> ranked;

  bool get found => quad != null;

  @override
  String toString() =>
      'edges: ${found ? 'found' : 'none'} via $strategy score=${score.toStringAsFixed(3)} '
      'candidates=$candidates in ${elapsed.inMilliseconds} ms';
}

/// A point in pixels.
typedef XY = ({double x, double y});

/// Finds the document in [bgr] (upright BGR, any size).
///
/// [aspectHint] favours the ID-1 (1.585) or ID-3 (1.42) shape. When
/// [searchArea] is given (normalised; the guide frame in ID / passport
/// modes) that area plus a 20 % margin is searched first, then the photo.
DetectionReport detectDocument(
  cv.Mat bgr, {
  double? aspectHint,
  ({double left, double top, double right, double bottom})? searchArea,
}) {
  final sw = Stopwatch()..start();
  if (searchArea != null) {
    final mx = (searchArea.right - searchArea.left) * 0.2;
    final my = (searchArea.bottom - searchArea.top) * 0.2;
    final l = (searchArea.left - mx).clamp(0.0, 1.0);
    final t = (searchArea.top - my).clamp(0.0, 1.0);
    final r = (searchArea.right + mx).clamp(0.0, 1.0);
    final b = (searchArea.bottom + my).clamp(0.0, 1.0);
    final rx = (l * bgr.cols).floor();
    final ry = (t * bgr.rows).floor();
    final rw = ((r - l) * bgr.cols).floor();
    final rh = ((b - t) * bgr.rows).floor();
    if (rw > 16 && rh > 16) {
      final roi = bgr.region(cv.Rect(rx, ry, rw, rh));
      final local = roi.clone();
      roi.dispose();
      final inner = _detect(local, aspectHint);
      local.dispose();
      if (inner.found) {
        Quad toFull(Quad q) => Quad(
          tl: Pt((rx + q.tl.x * rw) / bgr.cols, (ry + q.tl.y * rh) / bgr.rows),
          tr: Pt((rx + q.tr.x * rw) / bgr.cols, (ry + q.tr.y * rh) / bgr.rows),
          br: Pt((rx + q.br.x * rw) / bgr.cols, (ry + q.br.y * rh) / bgr.rows),
          bl: Pt((rx + q.bl.x * rw) / bgr.cols, (ry + q.bl.y * rh) / bgr.rows),
        );
        sw.stop();
        return DetectionReport(
          quad: toFull(inner.quad!),
          score: inner.score,
          elapsed: sw.elapsed,
          strategy: '${inner.strategy} (guide area)',
          candidates: inner.candidates,
          ranked: inner.ranked.map(toFull).toList(),
        );
      }
    }
  }
  final r = _detect(bgr, aspectHint);
  sw.stop();
  return DetectionReport(
    quad: r.quad,
    score: r.score,
    elapsed: sw.elapsed,
    strategy: r.strategy,
    candidates: r.candidates,
    ranked: r.ranked,
  );
}

DetectionReport _detect(cv.Mat bgr, double? target) {
  final hFull = bgr.rows;
  final wFull = bgr.cols;
  var scale = kDetectLongEdge / math.max(hFull, wFull);
  final cv.Mat small;
  if (scale < 1) {
    // Truncation like the reference's int(W * scale).
    small = cv.resize(bgr, (
      (wFull * scale).toInt(),
      (hFull * scale).toInt(),
    ), interpolation: cv.INTER_AREA);
  } else {
    small = bgr.clone();
    scale = 1;
  }
  final h = small.rows.toDouble();
  final w = small.cols.toDouble();
  final imgArea = h * w;

  final scored = <({List<XY> q, double score, String src})>[];
  for (final (name, map) in _candidateMaps(small)) {
    final retr = name == 'edges' ? cv.RETR_LIST : cv.RETR_EXTERNAL;
    final (contours, hierarchy) = cv.findContours(
      map,
      retr,
      cv.CHAIN_APPROX_SIMPLE,
    );
    for (var i = 0; i < contours.length; i++) {
      final c = contours[i];
      final area = cv.contourArea(c);
      if (area < kMinAreaFrac * imgArea) continue;
      final raw = _quadFromContour(c);
      if (raw == null) continue;
      var q = orderCorners(raw);
      if (name != 'edges') {
        // Region maps sit slightly inside the real edge: push 2 % outward.
        final cx = q.map((p) => p.x).reduce((a, b) => a + b) / 4;
        final cy = q.map((p) => p.y).reduce((a, b) => a + b) / 4;
        q = [
          for (final p in q)
            (
              x: (cx + (p.x - cx) * 1.02).clamp(0.0, w - 1),
              y: (cy + (p.y - cy) * 1.02).clamp(0.0, h - 1),
            ),
        ];
      }
      final qa = _polyArea(q);
      final frac = qa / imgArea;
      if (frac > 0.98) continue;
      final m = 0.02 * math.max(w, h);
      final onBorder = q
          .where(
            (p) => p.x < m || p.y < m || p.x > w - 1 - m || p.y > h - 1 - m,
          )
          .length;
      if (onBorder >= 3) continue;
      final rect = cornerAnglesScore(q);
      if (rect < 0.55) continue;
      final solidity = math.min(1.0, area / math.max(1.0, qa));
      var score = math.sqrt(frac) * rect * (0.5 + 0.5 * solidity);
      // Corners on the photo border are usually the border itself (busy
      // backgrounds merge with the frame). Only the edges map has an
      // artificial border line; in region maps a page touching the edge is
      // genuine (P0-4).
      if (name == 'edges') score *= math.pow(0.45, onBorder).toDouble();
      if (target != null) {
        final a = quadAspect(q);
        score *= math.max(0.05, 1.0 - (a - target).abs() / target * 2.5);
      }
      scored.add((q: q, score: score, src: name));
    }
    contours.dispose();
    hierarchy.dispose();
    map.dispose();
  }
  small.dispose();

  if (scored.isEmpty) {
    return const DetectionReport(
      quad: null,
      score: 0,
      elapsed: Duration.zero,
      strategy: 'none',
      candidates: 0,
    );
  }
  // Stable: the first candidate with the top score wins, as in the reference.
  final ranked = [...scored]..sort((a, b) => b.score.compareTo(a.score));
  var best = scored.first;
  for (final s in scored) {
    if (s.score > best.score) best = s;
  }
  Quad norm(List<XY> q) => Quad(
    tl: Pt(q[0].x / scale / wFull, q[0].y / scale / hFull),
    tr: Pt(q[1].x / scale / wFull, q[1].y / scale / hFull),
    br: Pt(q[2].x / scale / wFull, q[2].y / scale / hFull),
    bl: Pt(q[3].x / scale / wFull, q[3].y / scale / hFull),
  );
  return DetectionReport(
    quad: norm(best.q),
    score: best.score,
    elapsed: Duration.zero,
    strategy: best.src,
    candidates: scored.length,
    ranked: ranked.take(5).map((s) => norm(s.q)).toList(),
  );
}

/// The three binary maps from the reference: edges, bright regions (Otsu on
/// LAB-L) and low-saturation regions (inverse Otsu on HSV-S).
/// OpenCV's default border for morphology (`morphologyDefaultBorderValue()`,
/// DBL_MAX) leaves the photo edge out of erosion and dilation. dartcv4 passes
/// 0 instead, which ate regions touching the edge and broke parity with the
/// reference there (round 5, P0-4).
final cv.Scalar _neutralBorder = cv.Scalar.all(double.maxFinite);

cv.Mat _morph(cv.Mat src, int op, cv.Mat kernel, {int iterations = 1}) =>
    cv.morphologyEx(
      src,
      op,
      kernel,
      iterations: iterations,
      borderValue: _neutralBorder,
    );

cv.Mat _dilate(cv.Mat src, cv.Mat kernel) =>
    cv.dilate(src, kernel, borderValue: _neutralBorder);

/// The binary maps detection searches, in the reference's order (ties go to
/// the earlier map). Round 5, P0-4 adds "smooth" (the page is the big area
/// with no edges on a busy background) and its combinations with "pale".
@visibleForTesting
List<(String, cv.Mat)> candidateMaps(cv.Mat small) => _candidateMaps(small);

List<(String, cv.Mat)> _candidateMaps(cv.Mat small) {
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final lab = cv.cvtColor(small, cv.COLOR_BGR2Lab);
  final hsv = cv.cvtColor(small, cv.COLOR_BGR2HSV);
  final maps = <(String, cv.Mat)>[];

  // A) Edges with thresholds from the median brightness.
  final blur = cv.gaussianBlur(gray, (5, 5), 0);
  final m = medianOf(blur);
  final lo = math.max(10.0, 0.66 * m).toInt();
  final hi = math.min(255.0, math.max(40.0, 1.33 * m)).toInt();
  final edges = cv.canny(blur, lo.toDouble(), hi.toDouble());
  final k = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  final closed = _morph(edges, cv.MORPH_CLOSE, k, iterations: 2);
  final dil = _dilate(closed, k);
  // D) Smooth regions: on busy backgrounds (patterned cloth, wood grain) the
  // page is the big area with almost no edges. Invert the edges and open, so
  // thin gaps in the pattern vanish and the page stays one blob; dilate to
  // give back the rim the edge dilation ate.
  final inverted = cv.bitwiseNOT(dil);
  final k3 = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
  final smoothOpen = _morph(inverted, cv.MORPH_OPEN, k3);
  final smooth = _dilate(smoothOpen, k);
  maps.add(('smooth', smooth));
  // Close shapes that run off the photo (page partly outside the frame).
  cv.rectangle(
    dil,
    cv.Rect(0, 0, dil.cols, dil.rows),
    cv.Scalar.all(255),
    thickness: 2,
  );
  maps.add(('edges', dil));
  for (final x in [blur, edges, closed, inverted, k3, smoothOpen]) {
    x.dispose();
  }

  final k2 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  cv.Mat regions(cv.Mat channel, int type) {
    final b = cv.gaussianBlur(channel, (7, 7), 0);
    final (_, th) = cv.threshold(b, 0, 255, type | cv.THRESH_OTSU);
    final opened = _morph(th, cv.MORPH_OPEN, k2);
    final out = _morph(opened, cv.MORPH_CLOSE, k2, iterations: 2);
    for (final x in [b, th, opened]) {
      x.dispose();
    }
    return out;
  }

  // B) Pale paper / card on a darker surface.
  final labCh = cv.split(lab);
  final bright = regions(labCh[0], cv.THRESH_BINARY);
  maps.add(('bright', bright));
  labCh.dispose();
  // C) White / grey paper on a colourful surface.
  final hsvCh = cv.split(hsv);
  final lowsat = regions(hsvCh[1], cv.THRESH_BINARY_INV);
  maps.add(('lowsat', lowsat));
  hsvCh.dispose();

  // E) Smooth AND pale: on a busy, colourful background the page is the only
  // area that is both. A strong opening (about a tenth of the short side)
  // cuts thin bridges to pale patches of background; the page survives.
  final ko = math.max(15, (math.min(small.rows, small.cols) ~/ 10) | 1);
  final kBig = cv.getStructuringElement(cv.MORPH_ELLIPSE, (ko, ko));
  for (final (name, pale) in [
    ('smooth+lowsat', lowsat),
    ('smooth+bright', bright),
  ]) {
    final both = cv.bitwiseAND(smooth, pale);
    final opened = _morph(both, cv.MORPH_OPEN, kBig);
    maps.add((name, _morph(opened, cv.MORPH_CLOSE, k2, iterations: 2)));
    both.dispose();
    opened.dispose();
  }

  for (final x in [gray, lab, hsv, k, k2, kBig]) {
    x.dispose();
  }
  return maps;
}

/// Convex hull → approxPolyDP at growing ε → else the min-area rectangle when
/// the hull fills it (rounded card corners, slightly bent page).
List<XY>? _quadFromContour(cv.VecPoint c) {
  final hullMat = cv.convexHull(c);
  final hull = cv.VecPoint.fromMat(hullMat);
  hullMat.dispose();
  try {
    final peri = cv.arcLength(hull, true);
    for (final eps in const [0.02, 0.03, 0.04, 0.06, 0.08]) {
      final approx = cv.approxPolyDP(hull, eps * peri, true);
      if (approx.length == 4) {
        final pts = [
          for (var j = 0; j < 4; j++)
            (x: approx[j].x.toDouble(), y: approx[j].y.toDouble()),
        ];
        approx.dispose();
        return pts;
      }
      approx.dispose();
    }
    final box = cv.boxPoints(cv.minAreaRect(hull));
    final pts = [for (var j = 0; j < 4; j++) (x: box[j].x, y: box[j].y)];
    box.dispose();
    if (cv.contourArea(hull) / math.max(1.0, _polyArea(pts)) > 0.90) return pts;
    return null;
  } finally {
    hull.dispose();
  }
}

/// TL, TR, BR, BL exactly as the reference: argmin(x+y), argmin(y−x),
/// argmax(x+y), argmax(y−x).
List<XY> orderCorners(List<XY> pts) {
  XY by(double Function(XY) f, {required bool min}) =>
      pts.reduce((a, b) => (min ? f(b) < f(a) : f(b) > f(a)) ? b : a);
  return [
    by((p) => p.x + p.y, min: true),
    by((p) => p.y - p.x, min: true),
    by((p) => p.x + p.y, min: false),
    by((p) => p.y - p.x, min: false),
  ];
}

/// 1.0 = perfect rectangle, lower = more skewed.
double cornerAnglesScore(List<XY> q) {
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = q[(i + 3) % 4];
    final b = q[i];
    final c = q[(i + 1) % 4];
    final v1x = a.x - b.x;
    final v1y = a.y - b.y;
    final v2x = c.x - b.x;
    final v2y = c.y - b.y;
    final n =
        math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y) +
        1e-6;
    sum += ((v1x * v2x + v1y * v2y) / n).abs();
  }
  return math.max(0.0, 1.0 - 2.0 * sum / 4);
}

double quadAspect(List<XY> q) {
  double d(XY a, XY b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  final w = (d(q[1], q[0]) + d(q[2], q[3])) / 2;
  final h = (d(q[3], q[0]) + d(q[2], q[1])) / 2;
  return math.max(w, h) / math.max(1e-6, math.min(w, h));
}

double _polyArea(List<XY> q) {
  var s = 0.0;
  for (var i = 0; i < q.length; i++) {
    final a = q[i];
    final b = q[(i + 1) % q.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

/// Exact median of an 8-bit single-channel image (numpy's definition: the
/// mean of the two middle values when the count is even).
double medianOf(cv.Mat gray) {
  final hist = histogram8(gray);
  var n = 0;
  for (final c in hist) {
    n += c;
  }
  if (n == 0) return 0;
  int valueAt(int k) {
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc > k) return v;
    }
    return 255;
  }

  if (n.isOdd) return valueAt(n ~/ 2).toDouble();
  return (valueAt(n ~/ 2 - 1) + valueAt(n ~/ 2)) / 2;
}

/// numpy.percentile (linear interpolation) of an 8-bit single channel.
double percentile8(cv.Mat ch, double pct) {
  final hist = histogram8(ch);
  var n = 0;
  for (final c in hist) {
    n += c;
  }
  if (n == 0) return 0;
  final idx = pct / 100 * (n - 1);
  final lo = idx.floor();
  final hi = idx.ceil();
  int valueAt(int k) {
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc > k) return v;
    }
    return 255;
  }

  final a = valueAt(lo);
  final b = valueAt(hi);
  return a + (b - a) * (idx - lo);
}

List<int> histogram8(cv.Mat ch) {
  final hist = List<int>.filled(256, 0);
  final cont = ch.isContinuous ? ch : ch.clone();
  final data = cont.data;
  for (var i = 0; i < data.length; i++) {
    hist[data[i]]++;
  }
  if (!identical(cont, ch)) cont.dispose();
  return hist;
}

/// Fallback when nothing is found: the guide frame (ID / passport), else a
/// 5 % inset — never the exact full frame.
Quad fallbackQuad({Quad? guide}) => guide ?? Quad.full(inset: 0.05);

// ---------------------------------------------------------------------------
// Magnetic edges (round 3, P1-3): candidate lines and corners
// ---------------------------------------------------------------------------

/// Long straight lines and likely corners in [bgr], normalised to 0..1.
///
/// On an 800 px copy: Canny (median thresholds) → HoughLinesP (min length 8 %
/// of the short side, max gap 10 px) → segments on the same line merged.
/// Corners are intersections of near-perpendicular lines that lie near both
/// segments, plus the corners of the top five detected quads.
({List<(Pt, Pt)> lines, List<Pt> corners}) snapCandidates(
  cv.Mat bgr, {
  double? aspectHint,
}) {
  final s = math.min(1.0, kDetectLongEdge / math.max(bgr.rows, bgr.cols));
  final small = s < 1
      ? cv.resize(bgr, (
          (bgr.cols * s).toInt(),
          (bgr.rows * s).toInt(),
        ), interpolation: cv.INTER_AREA)
      : bgr.clone();
  final w = small.cols.toDouble();
  final h = small.rows.toDouble();
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final blur = cv.gaussianBlur(gray, (5, 5), 0);
  final m = medianOf(blur);
  final edges = cv.canny(
    blur,
    math.max(10.0, 0.66 * m),
    math.min(255.0, math.max(40.0, 1.33 * m)),
  );
  final minLen = 0.08 * math.min(w, h);
  final raw = cv.HoughLinesP(
    edges,
    1,
    math.pi / 180,
    40,
    minLineLength: minLen,
    maxLineGap: 10,
  );
  final segs = <(XY, XY)>[];
  if (!raw.isEmpty) {
    final data = raw.isContinuous ? raw.data : raw.clone().data;
    final ints = data.buffer.asInt32List(data.offsetInBytes, raw.rows * 4);
    for (var i = 0; i < raw.rows; i++) {
      segs.add((
        (x: ints[i * 4].toDouble(), y: ints[i * 4 + 1].toDouble()),
        (x: ints[i * 4 + 2].toDouble(), y: ints[i * 4 + 3].toDouble()),
      ));
    }
  }
  for (final x in [gray, blur, edges, raw]) {
    x.dispose();
  }

  final merged =
      mergeSegments(segs).where((l) => _len(l.$1, l.$2) >= minLen).toList()
        ..sort((a, b) => _len(b.$1, b.$2).compareTo(_len(a.$1, a.$2)));
  final lines = merged.take(40).toList();

  final corners = <XY>[];
  final near = 0.10 * math.min(w, h);
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      final (a1, a2) = lines[i];
      final (b1, b2) = lines[j];
      final ang = _angleDeg(a1, a2, b1, b2);
      if (ang < 60) continue; // near-perpendicular only (60°–90°)
      final p = _intersect(a1, a2, b1, b2);
      if (p == null) continue;
      if (p.x < -0.02 * w ||
          p.y < -0.02 * h ||
          p.x > 1.02 * w ||
          p.y > 1.02 * h) {
        continue;
      }
      if (_distToSegment(p, a1, a2) > near || _distToSegment(p, b1, b2) > near) {
        continue;
      }
      corners.add(p);
    }
  }
  small.dispose();

  // Corners of the best detection candidates (already normalised).
  final det = detectDocument(bgr, aspectHint: aspectHint);
  final out = <Pt>[for (final q in det.ranked) ...q.points];
  for (final c in corners) {
    final n = Pt(c.x / w, c.y / h).clamp01();
    if (out.every(
      (o) => (o.x - n.x).abs() * w > 6 || (o.y - n.y).abs() * h > 6,
    )) {
      out.add(n);
    }
  }
  return (
    lines: [
      for (final (a, b) in lines) (Pt(a.x / w, a.y / h), Pt(b.x / w, b.y / h)),
    ],
    corners: out,
  );
}

/// Merges segments that lie on the same line (within 3° and 6 px), keeping
/// the full extent of the group.
List<(XY, XY)> mergeSegments(List<(XY, XY)> segs) {
  final groups = <List<(XY, XY)>>[];
  final norms = <(double, double)>[]; // (theta in [0, π), rho)
  (double, double) normal((XY, XY) s) {
    final (a, b) = s;
    var theta = math.atan2(b.y - a.y, b.x - a.x) + math.pi / 2;
    theta %= math.pi;
    if (theta < 0) theta += math.pi;
    final rho = a.x * math.cos(theta) + a.y * math.sin(theta);
    return (theta, rho);
  }

  for (final seg in segs) {
    final (t, r) = normal(seg);
    var placed = false;
    for (var g = 0; g < groups.length; g++) {
      final (gt, gr) = norms[g];
      var dt = (t - gt).abs();
      var dr = (r - gr).abs();
      if (dt > math.pi / 2) {
        // Wrap-around: the same line seen with theta near 0 and near π.
        dt = math.pi - dt;
        dr = (r + gr).abs();
      }
      if (dt < 3 * math.pi / 180 && dr < 6) {
        groups[g].add(seg);
        placed = true;
        break;
      }
    }
    if (!placed) {
      groups.add([seg]);
      norms.add((t, r));
    }
  }

  return [
    for (final g in groups)
      () {
        // Direction of the longest segment; extent = all endpoints projected.
        final longest = g.reduce(
          (a, b) => _len(a.$1, a.$2) >= _len(b.$1, b.$2) ? a : b,
        );
        final (a, b) = longest;
        final len = _len(a, b);
        final dx = (b.x - a.x) / len;
        final dy = (b.y - a.y) / len;
        var tMin = double.infinity;
        var tMax = -double.infinity;
        for (final (p, q) in g) {
          for (final e in [p, q]) {
            final t = (e.x - a.x) * dx + (e.y - a.y) * dy;
            if (t < tMin) tMin = t;
            if (t > tMax) tMax = t;
          }
        }
        return (
          (x: a.x + dx * tMin, y: a.y + dy * tMin),
          (x: a.x + dx * tMax, y: a.y + dy * tMax),
        );
      }(),
  ];
}

double _len(XY a, XY b) =>
    math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

double _angleDeg(XY a1, XY a2, XY b1, XY b2) {
  final rx = a2.x - a1.x;
  final ry = a2.y - a1.y;
  final sx = b2.x - b1.x;
  final sy = b2.y - b1.y;
  final cos =
      (rx * sx + ry * sy).abs() / math.max(1e-9, _len(a1, a2) * _len(b1, b2));
  return math.acos(cos.clamp(0.0, 1.0)) * 180 / math.pi;
}

XY? _intersect(XY a1, XY a2, XY b1, XY b2) {
  final rx = a2.x - a1.x;
  final ry = a2.y - a1.y;
  final sx = b2.x - b1.x;
  final sy = b2.y - b1.y;
  final d = rx * sy - ry * sx;
  if (d.abs() < 1e-9) return null;
  final t = ((b1.x - a1.x) * sy - (b1.y - a1.y) * sx) / d;
  return (x: a1.x + rx * t, y: a1.y + ry * t);
}

double _distToSegment(XY p, XY a, XY b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final l2 = dx * dx + dy * dy;
  if (l2 < 1e-12) return _len(p, a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
  return _len(p, (x: a.x + dx * t, y: a.y + dy * t));
}

// ---------------------------------------------------------------------------
// Warp / rotate
// ---------------------------------------------------------------------------

/// Perspective-warps [src] to [quad] at the quad's own resolution — port of
/// the reference `warp()`. [aspect] (ID / passport) forces the output to the
/// real card shape. Cubic sampling, replicated border.
cv.Mat warpToQuad(cv.Mat src, Quad quad, {double? aspect}) {
  final w = src.cols.toDouble();
  final h = src.rows.toDouble();
  final q = orderCorners([
    for (final p in quad.points) (x: p.x * w, y: p.y * h),
  ]);
  double d(XY a, XY b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  var wt = math.max(d(q[2], q[3]), d(q[1], q[0])).toInt();
  var ht = math.max(d(q[1], q[2]), d(q[0], q[3])).toInt();
  if (aspect != null && aspect < 1) {
    // A portrait shape given as width / height (passport photo 35 × 45):
    // keep the height, set the width. Reading it as a card's long/short
    // ratio stretched it into landscape.
    wt = (ht * aspect).round();
  } else if (aspect != null) {
    // A card's long / short ratio, along whichever way the quad lies.
    if (wt >= ht) {
      ht = (wt / aspect).round();
    } else {
      wt = (ht / aspect).round();
    }
  }
  wt = math.max(1, wt);
  ht = math.max(1, ht);
  final srcPts = cv.VecPoint2f.fromList([
    for (final p in q) cv.Point2f(p.x, p.y),
  ]);
  final dstPts = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(wt - 1.0, 0),
    cv.Point2f(wt - 1.0, ht - 1.0),
    cv.Point2f(0, ht - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(srcPts, dstPts);
  final out = cv.warpPerspective(
    src,
    m,
    (wt, ht),
    flags: cv.INTER_CUBIC,
    borderMode: cv.BORDER_REPLICATE,
  );
  m.dispose();
  srcPts.dispose();
  dstPts.dispose();
  return out;
}

/// Returns a rotated copy, or [src] itself when there is nothing to do.
cv.Mat rotateQuarterTurns(cv.Mat src, int quarterTurns) {
  final t = ((quarterTurns % 4) + 4) % 4;
  if (t == 0) return src;
  final code = switch (t) {
    1 => cv.ROTATE_90_CLOCKWISE,
    2 => cv.ROTATE_180,
    _ => cv.ROTATE_90_COUNTERCLOCKWISE,
  };
  return cv.rotate(src, code);
}

/// Crop + rotate, with the source pre-shrunk (area averaging) when the target
/// is much smaller than the photo, so the warp never does the downsampling.
///
/// [src] belongs to the caller and is never disposed here. The result is
/// either [src] itself (nothing to do) or a new Mat the caller owns; use
/// `disposeUnless(src, result)` afterwards.
cv.Mat cropAndRotate(cv.Mat src, PageEdits edits, {int? maxLongEdge}) {
  var cur = src;
  // Replaces the working image, freeing the previous one exactly once and
  // never freeing the caller's src.
  void step(cv.Mat next) {
    if (identical(next, cur)) return;
    if (!identical(cur, src)) cur.dispose();
    cur = next;
  }

  final crop = edits.crop;
  // Keep ≥2× the target in the cropped part of the source so the final
  // INTER_AREA shrink does the quality work; exports (standard/full) pass
  // through at full size. Measured on the crop itself: a passport crop is
  // a third of the photo, and shrinking the whole photo to 2× the target
  // left it smaller than the target.
  if (maxLongEdge != null && crop != null && crop.area < 0.9) {
    final b = crop.bounds();
    final cropLong = math.max((b.right - b.left) * src.cols, (b.bottom - b.top) * src.rows);
    final k = maxLongEdge * 2 / math.max(cropLong, 1);
    if (k < 1) step(fitLongEdge(cur, (math.max(src.cols, src.rows) * k).round()));
  }
  if (crop != null) step(warpToQuad(cur, crop, aspect: edits.outputAspect));
  if (maxLongEdge != null) step(fitLongEdge(cur, maxLongEdge));
  step(rotateQuarterTurns(cur, edits.quarterTurns));
  return cur;
}

// ---------------------------------------------------------------------------
// Filters — port of the reference filters (always applied AFTER the warp).
// Every function returns a new Mat and frees all of its intermediates.
// ---------------------------------------------------------------------------

/// numpy's `astype(np.uint8)` truncates; OpenCV's convertTo rounds. Shifting
/// by just under half a level makes OpenCV truncate too, so the Dart output
/// matches the reference instead of drifting half a level per step.
const double _trunc = -0.4999;

/// Gray-world white balance, blended at [strength]. The gains are worked
/// out in float32 like the reference's numpy code (see [_meanF32]).
cv.Mat grayWorldWb(cv.Mat bgr, double strength) {
  final means = _meanF32(bgr);
  final f = Float32List(4);
  f[3] = means[0] + means[1];
  f[3] = (f[3] + means[2]) / 3; // means.mean(), in float32
  final ch = cv.split(bgr);
  final scaled = <cv.Mat>[
    for (var i = 0; i < 3; i++)
      ch[i].convertTo(
        cv.MatType.CV_8UC1,
        alpha: () {
          f[i] = f[3] / math.max(means[i], 1.0);
          f[i] = f[i] - 1.0;
          f[i] = f[i] * strength;
          f[i] = 1.0 + f[i];
          return f[i];
        }(),
        beta: _trunc,
      ),
  ];
  final out = cv.merge(cv.VecMat.fromList(scaled));
  for (final s in scaled) {
    s.dispose();
  }
  ch.dispose();
  return out;
}

/// numpy's `img.astype(float32).reshape(-1, 3).mean(axis=0)`: a running
/// float32 sum in pixel order, then a float32 divide. On a large page that
/// drifts ~0.1 level from the exact (double) mean OpenCV gives, and after
/// truncation and CLAHE the drift showed as 4-level differences.
List<double> _meanF32(cv.Mat bgr) {
  final cont = bgr.isContinuous ? bgr : bgr.clone();
  final d = cont.data;
  final acc = Float32List(3);
  for (var i = 0; i + 2 < d.length; i += 3) {
    acc[0] += d[i];
    acc[1] += d[i + 1];
    acc[2] += d[i + 2];
  }
  if (!identical(cont, bgr)) cont.dispose();
  final n = d.length ~/ 3;
  final out = Float32List(3);
  for (var c = 0; c < 3; c++) {
    out[c] = acc[c] / n;
  }
  return out;
}

cv.Mat claheL(cv.Mat bgr, double clip) {
  final lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
  final ch = cv.split(lab);
  final clahe = cv.createCLAHE(clipLimit: clip, tileGridSize: (8, 8));
  final l2 = clahe.apply(ch[0]);
  final merged = cv.merge(cv.VecMat.fromList([l2, ch[1], ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_Lab2BGR);
  for (final x in [l2, merged, lab]) {
    x.dispose();
  }
  ch.dispose();
  clahe.dispose();
  return out;
}

cv.Mat saturate(cv.Mat bgr, double factor) {
  final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
  final ch = cv.split(hsv);
  final s2 = ch[1].convertTo(cv.MatType.CV_8UC1, alpha: factor, beta: _trunc);
  final merged = cv.merge(cv.VecMat.fromList([ch[0], s2, ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_HSV2BGR);
  for (final x in [s2, merged, hsv]) {
    x.dispose();
  }
  ch.dispose();
  return out;
}

cv.Mat unsharp(cv.Mat bgr, double amount, double sigma) {
  final blur = cv.gaussianBlur(bgr, (0, 0), sigma);
  final out = cv.addWeighted(bgr, 1 + amount, blur, -amount, 0);
  blur.dispose();
  return out;
}

/// Rough sensor-noise sigma, as the reference `estimate_noise()`: the median
/// absolute deviation of the Laplacian of the gray image / 0.6745 / 2.
double estimateNoise(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final g32 = gray.convertTo(cv.MatType.CV_32FC1);
  final lap = cv.laplacian(g32, cv.MatType.CV_32F);
  final cont = lap.isContinuous ? lap : lap.clone();
  final bytes = cont.data;
  final values = Float32List.fromList(
    bytes.buffer.asFloat32List(bytes.offsetInBytes, cont.rows * cont.cols),
  );
  for (final m in [gray, g32, lap]) {
    m.dispose();
  }
  if (!identical(cont, lap)) cont.dispose();
  final med = _median(values);
  for (var i = 0; i < values.length; i++) {
    values[i] = (values[i] - med).abs();
  }
  return _median(values) / 0.6745 / 2.0;
}

/// numpy's median (mean of the two middle values for an even count), by
/// quickselect: O(n), reorders [v].
double _median(Float32List v) {
  final n = v.length;
  if (n == 0) return 0;
  double select(int k) {
    var lo = 0;
    var hi = n - 1;
    while (lo < hi) {
      final pivot = v[(lo + hi) >> 1];
      var i = lo;
      var j = hi;
      while (i <= j) {
        while (v[i] < pivot) {
          i++;
        }
        while (v[j] > pivot) {
          j--;
        }
        if (i <= j) {
          final t = v[i];
          v[i] = v[j];
          v[j] = t;
          i++;
          j--;
        }
      }
      if (k <= j) {
        hi = j;
      } else if (k >= i) {
        lo = i;
      } else {
        return v[k];
      }
    }
    return v[k];
  }

  if (n.isOdd) return select(n ~/ 2);
  final upper = select(n ~/ 2);
  // After selecting n/2 everything left of it is ≤ it: the lower middle is
  // the maximum of that part.
  var lower = v[0];
  for (var i = 1; i < n ~/ 2; i++) {
    if (v[i] > lower) lower = v[i];
  }
  return (lower + upper) / 2;
}

/// Removes sensor noise before any contrast step (round 6 reference
/// `_denoise`, the fast version): non-local means on brightness (Y) only,
/// template 5 / search 11; colour (Cr, Cb) is blotchy and low-frequency, so
/// a blur at 1/4 size is enough. Strength follows the measured noise,
/// `clamp(σ × 0.8, minH, maxH)`, so fine print isn't smeared, and a clean,
/// well-lit photo (σ < 1.5) is returned as is (a copy: callers dispose it).
/// About 6× faster than the old colour NLM (7 / 21).
cv.Mat denoise(cv.Mat bgr, {double minH = 3.0, double maxH = 6.0}) {
  final sigma = estimateNoise(bgr);
  if (sigma < 1.5) return bgr.clone();
  final strength = (sigma * 0.8).clamp(minH, maxH);
  final w = bgr.cols;
  final h = bgr.rows;
  final ycc = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb);
  final ch = cv.split(ycc);
  ycc.dispose();
  final y = cv.fastNlMeansDenoising(
    ch[0],
    h: strength,
    templateWindowSize: 5,
    searchWindowSize: 11,
  );
  final sm = (math.max(1, w ~/ 4), math.max(1, h ~/ 4));
  cv.Mat chroma(cv.Mat c) {
    final small = cv.resize(c, sm, interpolation: cv.INTER_AREA);
    final blur = cv.gaussianBlur(small, (0, 0), 1.2);
    final out = cv.resize(blur, (w, h), interpolation: cv.INTER_LINEAR);
    small.dispose();
    blur.dispose();
    return out;
  }

  final cr = chroma(ch[1]);
  final cb = chroma(ch[2]);
  ch.dispose();
  final merged = cv.merge(cv.VecMat.fromList([y, cr, cb]));
  final out = cv.cvtColor(merged, cv.COLOR_YCrCb2BGR);
  for (final m in [y, cr, cb, merged]) {
    m.dispose();
  }
  return out;
}

/// Instant, display-only clean-up for the first Enhance preview (reference
/// `denoise_preview`, ~10× cheaper than [denoise]): a bilateral filter
/// whose strength follows the measured noise. Replaced by the real result
/// once the page's cleaned base is ready. Always a new Mat.
cv.Mat denoisePreview(cv.Mat bgr) {
  final sigma = estimateNoise(bgr);
  if (sigma < 1.5) return bgr.clone();
  return cv.bilateralFilter(bgr, 5, (sigma * 6).clamp(15.0, 40.0), 3);
}

/// Parts of a page much blurrier than its sharpest part: camera shake or
/// focus fall-off (reference `blurry_regions`, round 6 P1-1). Returns the
/// (row, col) cells of a [grid] × [grid] split whose score is below
/// [ratio] × the best, or [] when the page is evenly sharp or has too
/// little detail to judge. Run on the cropped page, before filters.
///
/// Score: on each cell's strongest edges, median |Laplacian| / |gradient|,
/// about 1/σ for an edge blurred by σ whatever the ink's darkness.
List<(int, int)> blurryRegions(cv.Mat warped, {int grid = 3, double ratio = 0.5}) {
  final gray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
  var g = gray.convertTo(cv.MatType.CV_32FC1);
  gray.dispose();
  final s = 1200.0 / math.max(g.rows, g.cols);
  if (s < 1) {
    // numpy's `None, fx, fy`: OpenCV rounds the size from the scale.
    final r = cv.resize(g, (0, 0), fx: s, fy: s, interpolation: cv.INTER_AREA);
    g.dispose();
    g = r;
  }
  final smooth = cv.gaussianBlur(g, (0, 0), 0.8);
  g.dispose();
  final gx = cv.sobel(smooth, cv.MatType.CV_32F, 1, 0);
  final gy = cv.sobel(smooth, cv.MatType.CV_32F, 0, 1);
  final grad = cv.magnitude(gx, gy);
  final lapS = cv.laplacian(smooth, cv.MatType.CV_32F, ksize: 3);
  final zero = cv.Mat.zeros(lapS.rows, lapS.cols, lapS.type);
  final lap = cv.absDiff(lapS, zero);
  zero.dispose();
  final hh = smooth.rows;
  final ww = smooth.cols;
  final gradV = _floats(grad);
  final lapV = _floats(lap);
  for (final m in [smooth, gx, gy, grad, lapS, lap]) {
    m.dispose();
  }
  final my = (hh * 0.05).toInt();
  final mx = (ww * 0.05).toInt();
  final scores = <(int, int), double>{};
  for (var r = 0; r < grid; r++) {
    for (var c = 0; c < grid; c++) {
      final y0 = math.max(my, r * hh ~/ grid);
      final y1 = math.min(hh - my, (r + 1) * hh ~/ grid);
      final x0 = math.max(mx, c * ww ~/ grid);
      final x1 = math.min(ww - mx, (c + 1) * ww ~/ grid);
      if (y1 <= y0 || x1 <= x0) continue;
      final cell = Float32List((y1 - y0) * (x1 - x0));
      var n = 0;
      for (var y = y0; y < y1; y++) {
        final row = y * ww;
        for (var x = x0; x < x1; x++) {
          cell[n++] = gradV[row + x];
        }
      }
      final cut = math.max(60.0, _exactPercentile(cell, 97));
      final ratios = <double>[];
      for (var y = y0; y < y1; y++) {
        final row = y * ww;
        for (var x = x0; x < x1; x++) {
          final gr = gradV[row + x];
          if (gr > cut) ratios.add(lapV[row + x] / gr);
        }
      }
      if (ratios.length > 150) {
        scores[(r, c)] = _median(Float32List.fromList(ratios));
      }
    }
  }
  if (scores.length < 3) return const [];
  final best = scores.values.reduce(math.max);
  return [
    for (final e in scores.entries)
      if (e.value < ratio * best) e.key,
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
}

/// All values of a one-channel float Mat, row-major.
Float32List _floats(cv.Mat f32) {
  final cont = f32.isContinuous ? f32 : f32.clone();
  final bytes = cont.data;
  final out = Float32List.fromList(
    bytes.buffer.asFloat32List(bytes.offsetInBytes, cont.rows * cont.cols),
  );
  if (!identical(cont, f32)) cont.dispose();
  return out;
}

/// numpy's default (linear) percentile, exactly; reorders [v].
double _exactPercentile(Float32List v, double p) {
  if (v.isEmpty) return 0;
  v.sort();
  final pos = p / 100 * (v.length - 1);
  final lo = pos.floor();
  final hi = math.min(lo + 1, v.length - 1);
  return v[lo] + (v[hi] - v[lo]) * (pos - lo);
}

/// Paper brightness (illumination) without the text, as float32, same size.
cv.Mat background(cv.Mat ch8) {
  final h = ch8.rows;
  final w = ch8.cols;
  final s = 400.0 / math.max(h, w);
  final small = cv.resize(ch8, (
    math.max(1, (w * s).toInt()),
    math.max(1, (h * s).toInt()),
  ), interpolation: cv.INTER_AREA);
  final k = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  final dil = _dilate(small, k);
  final med = cv.medianBlur(dil, 21);
  final f = med.convertTo(cv.MatType.CV_32FC1);
  final g = cv.gaussianBlur(f, (0, 0), 6);
  final out = cv.resize(g, (w, h), interpolation: cv.INTER_CUBIC);
  for (final x in [small, k, dil, med, f, g]) {
    x.dispose();
  }
  return out;
}

/// `f / max(bg, floor) * scale` blended with `f`, per channel, as uint8.
cv.Mat _normalizeIllumination(
  cv.Mat ch8, {
  required double scale,
  double blend = 1.0,
}) {
  final bg = background(ch8);
  final floor = cv.Mat.fromScalar(
    bg.rows,
    bg.cols,
    cv.MatType.CV_32FC1,
    cv.Scalar.all(40),
  );
  final bgc = cv.max(bg, floor);
  final f = ch8.convertTo(cv.MatType.CV_32FC1);
  final norm = cv.divide(f, bgc, scale: scale);
  final mixed = blend >= 1
      ? norm
      : cv.addWeighted(norm, blend, f, 1 - blend, 0);
  final out = mixed.convertTo(cv.MatType.CV_8UC1, beta: _trunc);
  for (final x in [bg, floor, bgc, f, norm]) {
    x.dispose();
  }
  if (!identical(mixed, norm)) mixed.dispose();
  return out;
}

/// Stretch the L channel so [loPct]..[hiPct] spans 0..[span].
cv.Mat levelsL(cv.Mat bgr, double loPct, double hiPct, {double span = 252}) {
  final lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
  final ch = cv.split(lab);
  final lo = percentile8(ch[0], loPct);
  final hi = percentile8(ch[0], hiPct);
  final k = span / math.max(1.0, hi - lo);
  final l2 = ch[0].convertTo(
    cv.MatType.CV_8UC1,
    alpha: k,
    beta: -lo * k + _trunc,
  );
  final merged = cv.merge(cv.VecMat.fromList([l2, ch[1], ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_Lab2BGR);
  for (final x in [l2, merged, lab]) {
    x.dispose();
  }
  ch.dispose();
  return out;
}

/// "Auto (colour)": clean, bright page, colours kept. For paper documents.
///
/// Round 5, P0-2 (reference `filter_auto_color`): after the denoise every step
/// works in float32 and the image is rounded to 8-bit once, at the end.
/// Rounding between steps and then stretching contrast is what drew grey
/// "marble" patches and contour lines on plain paper.
cv.Mat autoFilter(cv.Mat bgr) {
  final dn = denoise(bgr);
  final out = autoFrom(dn);
  dn.dispose();
  return out;
}

/// [autoFilter] after its denoise, from an already cleaned page (round 6,
/// P0-2: each page is cleaned once and every filter starts from that).
cv.Mat autoFrom(cv.Mat dn) {
  final m = cv.mean(dn);
  final means = [m.val1, m.val2, m.val3];
  final avg = (means[0] + means[1] + means[2]) / 3;
  final ch8 = cv.split(dn);
  final f = <cv.Mat>[];
  for (var i = 0; i < 3; i++) {
    // Gray-world white balance (strength 0.6), in float.
    final c = ch8[i].convertTo(
      cv.MatType.CV_32FC1,
      alpha: 1 + 0.6 * (avg / math.max(means[i], 1.0) - 1),
    );
    // Shadow removal: divide by the smooth background (clamped divisor), blend 75 %.
    final c8 = c.convertTo(cv.MatType.CV_8UC1, beta: _trunc);
    final bg = background(c8);
    final floor = cv.Mat.fromScalar(
      bg.rows,
      bg.cols,
      cv.MatType.CV_32FC1,
      cv.Scalar.all(40),
    );
    final bgc = cv.max(bg, floor);
    final norm = cv.divide(c, bgc, scale: 245);
    f.add(cv.addWeighted(norm, 0.75, c, 0.25, 0));
    for (final x in [c, c8, bg, floor, bgc, norm]) {
      x.dispose();
    }
  }
  ch8.dispose();
  final merged = cv.merge(cv.VecMat.fromList(f));
  for (final x in f) {
    x.dispose();
  }
  // To float Lab (L 0..100).
  final unit = merged.convertTo(cv.MatType.CV_32FC3, alpha: 1 / 255);
  merged.dispose();
  final clipped = _clip(unit, 0, 1);
  unit.dispose();
  final lab = cv.cvtColor(clipped, cv.COLOR_BGR2Lab);
  clipped.dispose();
  final labCh = cv.split(lab);
  lab.dispose();
  // Global levels on L (1 / 99.5 %).
  final [lo, hi] = _percentiles(labCh[0], const [1, 99.5]);
  final k = 99.0 / math.max(1e-3, hi - lo);
  final stretched = labCh[0].convertTo(
    cv.MatType.CV_32FC1,
    alpha: k,
    beta: -lo * k,
  );
  final l = _clip(stretched, 0, 100);
  stretched.dispose();
  final w = whitenPaper(l, labCh[1], labCh[2]);
  if (!identical(w.l, l)) l.dispose();
  // Neutral paper, +10 % colour elsewhere.
  final cA = w.chroma == null
      ? labCh[1].convertTo(cv.MatType.CV_32FC1, alpha: 1.10)
      : cv.multiply(labCh[1], w.chroma!, scale: 1.10);
  final cB = w.chroma == null
      ? labCh[2].convertTo(cv.MatType.CV_32FC1, alpha: 1.10)
      : cv.multiply(labCh[2], w.chroma!, scale: 1.10);
  w.chroma?.dispose();
  final lab2 = cv.merge(cv.VecMat.fromList([w.l, cA, cB]));
  for (final x in [w.l, cA, cB]) {
    x.dispose();
  }
  labCh.dispose();
  final bgrF = cv.cvtColor(lab2, cv.COLOR_Lab2BGR);
  lab2.dispose();
  final f255 = bgrF.convertTo(cv.MatType.CV_32FC3, alpha: 255);
  bgrF.dispose();
  // Unsharp, then the only rounding.
  final blur = cv.gaussianBlur(f255, (0, 0), 1.2);
  final sharp = cv.addWeighted(f255, 1.35, blur, -0.35, 0);
  final out = sharp.convertTo(cv.MatType.CV_8UC3);
  for (final x in [f255, blur, sharp]) {
    x.dispose();
  }
  return out;
}

/// Reference `_whiten_paper` (P0-2), on float Lab channels: if the page is
/// mostly plain paper with dark text (few mid-tones), push the paper to pure
/// white with a smoothstep from 70 % of the paper level, so there's no
/// visible edge or step; text below that keeps its weight. Photos and
/// packaging have many mid-tones, and the effect fades out (never a hard
/// switch). Returns the new L and the chroma multiplier (null = unchanged).
/// Statistics come from a ≤ 1000 px sample; the curve runs at full size.
({cv.Mat l, cv.Mat? chroma}) whitenPaper(cv.Mat l, cv.Mat a, cv.Mat b) {
  final chroma = cv.magnitude(a, b);
  final ls = _sample(l);
  final cs = _sample(chroma);
  final p40 = _percentileOf(Float32List.fromList(ls), 40);
  final paper = Float32List.fromList([
    for (var i = 0; i < ls.length; i++)
      if (cs[i] < 12 && ls[i] > p40) ls[i],
  ]);
  if (paper.isEmpty) {
    chroma.dispose();
    return (l: l, chroma: null);
  }
  final pL = _percentileOf(paper, 15);
  var midCount = 0;
  for (final v in ls) {
    if (v > 0.35 * pL && v < 0.80 * pL) midCount++;
  }
  final mid = midCount / ls.length;
  final strength = ((0.10 - mid) / 0.03).clamp(0.0, 1.0);
  if (strength == 0) {
    chroma.dispose();
    return (l: l, chroma: null);
  }
  final t0 = 0.70 * pL;
  final span = math.max(1e-3, pL - t0);
  // x = clip((L − t0) / span, 0, 1); s = x²(3 − 2x) · strength.
  final xr = l.convertTo(
    cv.MatType.CV_32FC1,
    alpha: 1 / span,
    beta: -t0 / span,
  );
  final x = _clip(xr, 0, 1);
  final x2 = cv.multiply(x, x);
  final term = x.convertTo(cv.MatType.CV_32FC1, alpha: -2, beta: 3);
  final s = cv.multiply(x2, term, scale: strength);
  // L2 = L + s · (100 − L)
  final room = l.convertTo(cv.MatType.CV_32FC1, alpha: -1, beta: 100);
  final lift = cv.multiply(s, room);
  final l2 = cv.add(l, lift);
  // k = 1 − 0.8 · s · (chroma < 20): fade the paper tint to neutral.
  final (_, pale) = cv.threshold(chroma, 20, 1, cv.THRESH_BINARY_INV);
  final sPale = cv.multiply(s, pale);
  final k = sPale.convertTo(cv.MatType.CV_32FC1, alpha: -0.8, beta: 1);
  for (final m in [chroma, xr, x, x2, term, s, room, lift, pale, sPale]) {
    m.dispose();
  }
  return (l: l2, chroma: k);
}

/// Clamps a float Mat to [lo, hi].
cv.Mat _clip(cv.Mat f, double lo, double hi) {
  final (_, top) = cv.threshold(f, hi, hi, cv.THRESH_TRUNC);
  final floor = cv.Mat.fromScalar(f.rows, f.cols, f.type, cv.Scalar.all(lo));
  final out = cv.max(top, floor);
  top.dispose();
  floor.dispose();
  return out;
}

/// Every pixel of a one-channel float Mat taken on a grid so at most about
/// a million values are read (nearest neighbour keeps the distribution).
Float32List _sample(cv.Mat f32) {
  final long = math.max(f32.cols, f32.rows);
  final small = long > 1000
      ? cv.resize(f32, (
          (f32.cols * 1000 / long).round(),
          (f32.rows * 1000 / long).round(),
        ), interpolation: cv.INTER_NEAREST)
      : f32.clone();
  final bytes = small.data;
  final out = Float32List.fromList(
    bytes.buffer.asFloat32List(bytes.offsetInBytes, small.rows * small.cols),
  );
  small.dispose();
  return out;
}

/// Percentiles of a float Mat, from a sample.
List<double> _percentiles(cv.Mat f32, List<double> pcts) {
  final v = _sample(f32);
  return [for (final p in pcts) _percentileOf(v, p)];
}

/// numpy-style percentile from a 4096-bin histogram (linear time; within
/// 1/4096 of the value range, far below one output level).
double _percentileOf(Float32List values, double p) {
  if (values.isEmpty) return 0;
  var lo = values[0];
  var hi = values[0];
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo < 1e-6) return lo;
  const bins = 4096;
  final width = (hi - lo) / bins;
  final hist = Int32List(bins);
  for (final v in values) {
    hist[math.min(bins - 1, ((v - lo) / width).floor())]++;
  }
  final target = p / 100 * (values.length - 1);
  var acc = 0;
  for (var i = 0; i < bins; i++) {
    final next = acc + hist[i];
    if (next > target) {
      // Spread the bin's values evenly across it.
      return lo + width * (i + (target - acc + 0.5) / hist[i]);
    }
    acc = next;
  }
  return hi;
}

/// "ID colour" (default in ID / passport): no background whitening — a card
/// is not white paper. Clean, sharp, true colours.
cv.Mat idColorFilter(cv.Mat bgr) {
  // Cards have fine guilloche print and small text: denoise capped low.
  final dn = denoise(bgr, minH: cardDenoiseMin, maxH: cardDenoiseMax);
  final out = idColorFrom(dn);
  dn.dispose();
  return out;
}

/// The ID colour denoise range (the reference's `filter_id_color`).
const double cardDenoiseMin = 2.0;
const double cardDenoiseMax = 3.0;

/// [idColorFilter] after its denoise, from an already cleaned page.
cv.Mat idColorFrom(cv.Mat dn) {
  final wb = grayWorldWb(dn, 0.5);
  final cl = claheL(wb, 1.6);
  wb.dispose();
  final sat = saturate(cl, 1.15);
  cl.dispose();
  final lv = levelsL(sat, 1, 99, span: 250);
  sat.dispose();
  final out = unsharp(lv, 0.6, 1.0);
  lv.dispose();
  return out;
}

/// "B&W print": pure black text on white, for photocopies.
cv.Mat bwPrintFilter(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final smooth = cv.bilateralFilter(gray, 5, 30, 30);
  final norm = _normalizeIllumination(smooth, scale: 255);
  final block = math.max(15, (math.min(gray.rows, gray.cols) ~/ 40) | 1);
  final bw = cv.adaptiveThreshold(
    norm,
    255,
    cv.ADAPTIVE_THRESH_GAUSSIAN_C,
    cv.THRESH_BINARY,
    block,
    12,
  );
  final med = cv.medianBlur(bw, 3);
  final out = cv.cvtColor(med, cv.COLOR_GRAY2BGR);
  for (final x in [gray, smooth, norm, bw, med]) {
    x.dispose();
  }
  return out;
}

cv.Mat _normalizedGray(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final norm = cv.Mat.empty();
  cv.normalize(gray, norm, alpha: 0, beta: 255, normType: cv.NORM_MINMAX);
  gray.dispose();
  return norm;
}

/// Auto → gray → normalise.
cv.Mat grayscaleFilter(cv.Mat bgr) {
  final auto = autoFilter(bgr);
  final out = grayscaleFrom(auto);
  auto.dispose();
  return out;
}

/// [grayscaleFilter] from an [autoFilter] result (Enhance caches that).
cv.Mat grayscaleFrom(cv.Mat auto) {
  final gray = _normalizedGray(auto);
  final out = cv.cvtColor(gray, cv.COLOR_GRAY2BGR);
  gray.dispose();
  return out;
}

/// Auto + 25 % saturation and a little contrast.
cv.Mat colorBoostFilter(cv.Mat bgr) {
  final auto = autoFilter(bgr);
  final out = colorBoostFrom(auto);
  auto.dispose();
  return out;
}

/// [colorBoostFilter] from an [autoFilter] result (Enhance caches that).
cv.Mat colorBoostFrom(cv.Mat auto) {
  final sat = saturate(auto, 1.25);
  final out = sat.convertTo(cv.MatType.CV_8UC3, alpha: 1.1, beta: -12);
  sat.dispose();
  return out;
}

/// Filters built on [autoFilter]; Enhance reuses one Auto result for them.
bool usesAutoBase(FilterType f) =>
    f == FilterType.auto || f == FilterType.colorBoost || f == FilterType.grayscale;

cv.Mat applyFilter(cv.Mat bgr, FilterType filter) => switch (filter) {
  FilterType.original => bgr.clone(),
  FilterType.auto => autoFilter(bgr),
  FilterType.idColor => idColorFilter(bgr),
  FilterType.colorBoost => colorBoostFilter(bgr),
  FilterType.grayscale => grayscaleFilter(bgr),
  FilterType.bwPrint => bwPrintFilter(bgr),
};

// ---------------------------------------------------------------------------
// Cleaned base (round 6, P0-2): each page is cleaned (denoised) once, at
// export size, and every filter, preview and export starts from that.
// ---------------------------------------------------------------------------

/// The page's noise removed: the document strength (3–6), or the ID colour
/// one (2–3) for cards, whose fine print strong cleaning smears. [quick]
/// (low-RAM phones, P0-4): a quiet photo (σ < 2.5) gets the bilateral
/// clean-up instead of non-local means.
cv.Mat cleanPage(cv.Mat warped, {bool card = false, bool quick = false}) {
  if (quick && estimateNoise(warped) < 2.5) return denoisePreview(warped);
  return card
      ? denoise(warped, minH: cardDenoiseMin, maxH: cardDenoiseMax)
      : denoise(warped);
}

/// [filter] on a cleaned page: the filter's own steps without its
/// denoise. `original` isn't a cleaned look (it's the raw page): callers
/// render it from the original instead; here it is just a copy.
cv.Mat applyFilterFromClean(cv.Mat clean, FilterType filter) => switch (filter) {
  FilterType.original => clean.clone(),
  FilterType.auto => autoFrom(clean),
  FilterType.idColor => idColorFrom(clean),
  FilterType.colorBoost => _fromAuto(clean, colorBoostFrom),
  FilterType.grayscale => _fromAuto(clean, grayscaleFrom),
  FilterType.bwPrint => bwPrintFilter(clean),
};

cv.Mat _fromAuto(cv.Mat clean, cv.Mat Function(cv.Mat) then) {
  final auto = autoFrom(clean);
  final out = then(auto);
  auto.dispose();
  return out;
}

/// Applies the brightness / contrast sliders as `a·x + b`, clamped to 0..255.
/// Same mapping as the live preview matrix.
cv.Mat brightnessContrast(cv.Mat bgr, PageEdits edits) {
  if (!edits.hasSliders) return bgr.clone();
  final t = edits.sliderTransform;
  return bgr.convertTo(cv.MatType.CV_8UC3, alpha: t.alpha, beta: t.beta);
}

/// Dedicated image for text recognition (never the user's filter).
cv.Mat ocrImage(cv.Mat warpedBgr) {
  final gray = cv.cvtColor(warpedBgr, cv.COLOR_BGR2GRAY);
  final smooth = cv.bilateralFilter(gray, 5, 30, 30);
  final clahe = cv.createCLAHE(clipLimit: 1.8, tileGridSize: (8, 8));
  final out = clahe.apply(smooth);
  gray.dispose();
  smooth.dispose();
  clahe.dispose();
  return out;
}

// ---------------------------------------------------------------------------
// Capture checks
// ---------------------------------------------------------------------------

/// Sharpness of a card (P0-2): warp [quad] out of [img] to the real card
/// shape, scale to 1000 px wide, Laplacian variance.
double cardSharpnessOf(cv.Mat img, Quad quad, double aspect) {
  final card = warpToQuad(img, quad, aspect: aspect);
  final landscape = card.cols >= card.rows
      ? card
      : cv.rotate(card, cv.ROTATE_90_CLOCKWISE);
  final w1000 = cv.resize(landscape, (
    1000,
    (1000 * landscape.rows / landscape.cols).round(),
  ), interpolation: cv.INTER_AREA);
  final gray = cv.cvtColor(w1000, cv.COLOR_BGR2GRAY);
  final lap = cv.laplacian(gray, cv.MatType.CV_64F);
  final (mean, std) = cv.meanStdDev(lap);
  final v = std.val1 * std.val1;
  for (final m in [w1000, gray, lap]) {
    m.dispose();
  }
  mean.dispose();
  std.dispose();
  if (!identical(landscape, card)) landscape.dispose();
  card.dispose();
  return v;
}

/// Variance of the Laplacian on a 1000 px copy (reference `sharpness()`), and
/// the mean brightness of that copy. Low sharpness = blurry; low brightness =
/// dark. Thresholds live in `CaptureChecks`.
({double sharpness, double brightness}) captureStats(cv.Mat bgr) {
  final s = 1000.0 / math.max(bgr.rows, bgr.cols);
  final small = cv.resize(bgr, (
    (bgr.cols * s).toInt(),
    (bgr.rows * s).toInt(),
  ));
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final lap = cv.laplacian(gray, cv.MatType.CV_64F);
  final (mean, std) = cv.meanStdDev(lap);
  final variance = std.val1 * std.val1;
  final brightness = cv.mean(gray).val1;
  for (final x in [small, gray, lap]) {
    x.dispose();
  }
  mean.dispose();
  std.dispose();
  return (sharpness: variance, brightness: brightness);
}

// ---------------------------------------------------------------------------
// Full renders
// ---------------------------------------------------------------------------

/// Applies [edits] to the upright original at [path]. Crop first, then
/// filter, so the table never feeds the filter statistics. Never enlarges.
///
/// [previewDecode] (placeholders only) decodes at a reduced size when the
/// crop allows it; see [readUprightForCrop]. [timer] gets a lap per step.
cv.Mat renderEdits(String path, PageEdits edits, {int? maxLongEdge, bool previewDecode = false, StepTimer? timer}) {
  final img = previewDecode && maxLongEdge != null
      ? readUprightForCrop(path, edits.crop, maxLongEdge)
      : readUpright(path);
  timer?.lap('decode ${img.cols}×${img.rows}');
  // A passport photo never needs more than [photoFinishLongEdge]: crop
  // straight to it rather than at the camera's full resolution.
  final cap = edits.photoWidthMm == null ? maxLongEdge : math.min(maxLongEdge ?? photoFinishLongEdge, photoFinishLongEdge);
  final cropped = cropAndRotate(img, edits, maxLongEdge: cap);
  disposeUnless(img, cropped);
  timer?.lap('crop to ${cropped.cols}×${cropped.rows}');
  final filtered = applyFilter(cropped, edits.filter);
  cropped.dispose();
  timer?.lap('filter ${edits.filter.name}');
  return finishEdits(filtered, edits, timer: timer);
}

/// What comes after the filter: the sliders, a passport photo's finish and
/// signatures. Takes ownership of [filtered].
cv.Mat finishEdits(cv.Mat filtered, PageEdits edits, {StepTimer? timer}) {
  final adjusted = brightnessContrast(filtered, edits);
  filtered.dispose();
  final backed = _withPhotoFinish(adjusted, edits);
  disposeUnless(adjusted, backed);
  final out = withOverlays(backed, edits.overlays);
  disposeUnless(backed, out);
  timer?.lap('sliders/overlays');
  return out;
}

/// Round 6, P0-2: the page cropped, turned and cleaned once at [longEdge]
/// (export size). Every filter, the Enhance preview and the export start
/// from it, so the expensive clean-up never runs twice for a page.
cv.Mat renderCleanBase(
  String originalPath,
  PageEdits edits, {
  required int longEdge,
  bool card = false,
  bool quick = false,
  StepTimer? timer,
}) {
  final img = readUprightForCrop(originalPath, edits.crop, longEdge);
  timer?.lap('decode ${img.cols}×${img.rows}');
  final cropped = cropAndRotate(img, edits, maxLongEdge: longEdge);
  disposeUnless(img, cropped);
  timer?.lap('crop to ${cropped.cols}×${cropped.rows}');
  final clean = cleanPage(cropped, card: card, quick: quick);
  cropped.dispose();
  timer?.lap('clean${quick ? ' (low-RAM)' : ''}');
  return clean;
}

/// A page from its cleaned base ([renderCleanBase]'s file): the filter and
/// what follows it, at most [maxLongEdge]. Not for `original` (the raw
/// page; render that from the original).
cv.Mat renderFromClean(
  String basePath,
  PageEdits edits, {
  int? maxLongEdge,
  StepTimer? timer,
}) {
  final base = cv.imread(basePath, flags: cv.IMREAD_COLOR);
  if (base.isEmpty) {
    base.dispose();
    throw StateError('Could not read $basePath');
  }
  final sized = maxLongEdge == null ? base : fitLongEdge(base, maxLongEdge);
  disposeUnless(base, sized);
  timer?.lap('load cleaned base ${sized.cols}×${sized.rows}');
  final filtered = applyFilterFromClean(sized, edits.filter);
  sized.dispose();
  timer?.lap('filter ${edits.filter.name}');
  return finishEdits(filtered, edits, timer: timer);
}

/// An ID card / passport side from its cleaned base, at real size for
/// [dpi] (see [renderCard]).
cv.Mat cardFromClean(
  String basePath,
  PageEdits edits, {
  required double widthMm,
  required double heightMm,
  required int dpi,
  StepTimer? timer,
}) {
  final tw = (widthMm / 25.4 * dpi).round();
  final th = (heightMm / 25.4 * dpi).round();
  final full = renderFromClean(basePath, edits, maxLongEdge: 2 * math.max(tw, th), timer: timer);
  return _toCardSize(full, tw, th, timer);
}

/// Background colours (BGR): white, and a deep passport-studio blue
/// #1F4E8C.
cv.Scalar? photoBackgroundColor(PhotoBackground b) => switch (b) {
  PhotoBackground.original => null,
  PhotoBackground.white => cv.Scalar(255, 255, 255),
  PhotoBackground.darkBlue => cv.Scalar(140, 78, 31),
};

/// Passport photo finish: [enhancePhoto] (if on), then the background
/// colour. The person mask (whole upright photo) is warped with the same
/// crop as the photo. Returns [page] itself when there's nothing to do.
cv.Mat _withPhotoFinish(cv.Mat page, PageEdits edits) {
  final color = photoBackgroundColor(edits.photoBackground);
  final enhance = edits.photoEnhance;
  if (color == null && enhance == PhotoEnhance.off) return page;
  cv.Mat? warped;
  final path = edits.backgroundMaskPath;
  if (path != null) {
    final mask = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
    if (mask.isEmpty) {
      mask.dispose();
    } else {
      // The crop is in fractions of the upright photo, so it fits the mask too.
      warped = cropAndRotate(mask, edits);
      disposeUnless(mask, warped);
    }
  }
  // A passport photo never needs more than this (35 × 45 mm at ~900 dpi;
  // the largest pixel size offered is 1200 × 1543), and the finish holds
  // several full-size float copies: a 48 MP crop would need gigabytes.
  final long = math.max(page.cols, page.rows);
  final capped = long <= photoFinishLongEdge
      ? page
      : cv.resize(
          page,
          ((page.cols * photoFinishLongEdge / long).round(), (page.rows * photoFinishLongEdge / long).round()),
          interpolation: cv.INTER_AREA,
        );
  try {
    final out = finishPhoto(capped, warped, color: color, enhance: enhance);
    if (!identical(capped, page) && !identical(out, capped)) capped.dispose();
    return out;
  } finally {
    warped?.dispose();
  }
}

/// The long edge a passport photo is finished (enhanced, background
/// changed) at, at most.
const photoFinishLongEdge = 1600;

/// [enhancePhoto] then [replaceBackground] on [img] with [mask] (8-bit,
/// 255 = person, any size, or null). Returns [img] itself when neither
/// applies.
cv.Mat finishPhoto(
  cv.Mat img,
  cv.Mat? mask, {
  cv.Scalar? color,
  PhotoEnhance enhance = PhotoEnhance.off,
}) {
  var out = img;
  if (enhance != PhotoEnhance.off) {
    final sized = mask == null
        ? null
        : cv.resize(mask, (img.cols, img.rows), interpolation: cv.INTER_LINEAR);
    out = enhancePhoto(img, sized, enhance);
    sized?.dispose();
  }
  if (color != null && mask != null) {
    final backed = replaceBackground(out, mask, color);
    if (!identical(out, img)) out.dispose();
    out = backed;
  }
  return out;
}

/// Passport photo Enhance: what a photo studio does, kept natural.
///  1. White balance from the wall (a light, near-neutral wall is a grey
///     card for the room's light), only with a [person] mask.
///  2. Exposure from the whole photo's highlights, one gain on linear
///     light with a soft shoulder. Never judged from skin, so darker skin
///     isn't lightened.
///  3. Shadow fill: only parts of the face and neck clearly darker than
///     the rest, lifted by a smooth field (texture kept); hair and clothes
///     keep their tone.
///  4. Skin softened (edge-preserving), keeping fine texture so it isn't
///     plastic; smooth more than natural.
///  5. Eyes, brows, lips and hair sharpened a little; skin not.
/// [person]: 8-bit, 255 = person, the size of [img], or null (skin found
/// by colour alone). Always returns a new BGR image.
cv.Mat enhancePhoto(cv.Mat img, cv.Mat? person, PhotoEnhance level) {
  final (soften, keep, sharpen, fill) = switch (level) {
    PhotoEnhance.off => (0.0, 1.0, 0.0, 0.0),
    PhotoEnhance.natural => (0.45, 0.45, 0.30, 0.60),
    PhotoEnhance.smooth => (0.75, 0.30, 0.25, 0.60),
  };
  if (level == PhotoEnhance.off) {
    return img.channels == 1 ? cv.cvtColor(img, cv.COLOR_GRAY2BGR) : img.clone();
  }
  final tmp = <cv.Mat>[];
  cv.Mat t(cv.Mat m) {
    tmp.add(m);
    return m;
  }

  // Each step runs in a _stage so its full-size working copies are freed
  // before the next (a 2 MP float image is 24 MB).
  try {
    var bgr = img.channels == 1 ? t(cv.cvtColor(img, cv.COLOR_GRAY2BGR)) : img;
    final (w, h) = (bgr.cols, bgr.rows);
    final long = math.max(w, h);
    if (person != null) bgr = t(_wallWhiteBalance(bgr, person));
    bgr = t(_exposure(bgr));

    // Skin: a soft YCrCb box (works across skin tones), on the person.
    final skin = t(
      _stage((s) {
        final ycc = cv.split(s(cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb)));
        final (cr, cb) = (s(ycc[1].clone()), s(ycc[2].clone()));
        ycc.dispose();
        cv.Mat soft(cv.Mat v, double lo, double hi, double f) => s(
          _clamp01(
            s(
              cv.min(
                s(v.convertTo(cv.MatType.CV_32FC1, alpha: 1 / f, beta: -lo / f)),
                s(v.convertTo(cv.MatType.CV_32FC1, alpha: -1 / f, beta: hi / f)),
              ),
            ),
            s.call,
          ),
        );
        final colour = s(cv.multiply(soft(cr, 133, 180, 6), soft(cb, 77, 130, 6)));
        if (person == null) return colour;
        final onPerson = s(person.convertTo(cv.MatType.CV_32FC1, alpha: 2 / 255, beta: -1));
        return cv.multiply(colour, s(_clamp01(onPerson, s.call)));
      }),
    );
    final size = math.max(60.0, math.sqrt(cv.sum(skin).val1));

    // Broad light, measured on a small copy and scaled back up.
    final k = math.min(1.0, 256 / long);
    final small = (math.max(1, (w * k).round()), math.max(1, (h * k).round()));
    cv.Mat broad(cv.Mat m, double sigma, _Track s) => s(
      cv.resize(
        s(cv.gaussianBlur(s(cv.resize(m, small, interpolation: cv.INTER_AREA)), (0, 0), math.max(1, sigma * k))),
        (w, h),
        interpolation: cv.INTER_LINEAR,
      ),
    );

    // Shadow fill on lightness, only on and around skin: dark hair and
    // clothes keep their tone.
    bgr = t(
      _stage((s) {
        final lab = cv.split(s(cv.cvtColor(bgr, cv.COLOR_BGR2Lab)));
        final (lL, la, lb) = (s(lab[0].clone()), s(lab[1].clone()), s(lab[2].clone()));
        lab.dispose();
        final base = broad(lL, size / 5, s.call);
        final (_, skinMask) = cv.threshold(skin, 0.5, 255, cv.THRESH_BINARY);
        final skin8 = s(s(skinMask).convertTo(cv.MatType.CV_8UC1));
        if (cv.countNonZero(skin8) <= 200) return bgr.clone();
        final ref = _percentile(base, skin8, 0.75);
        // lift = max(0.92 · ref − base, 0) · fill
        final (_, lift) = cv.threshold(
          s(base.convertTo(cv.MatType.CV_32FC1, alpha: -fill, beta: 0.92 * ref * fill)),
          0,
          0,
          cv.THRESH_TOZERO,
        );
        s(lift);
        final near = s(_clamp01(s(broad(skin, size / 12, s.call).convertTo(cv.MatType.CV_32FC1, alpha: 2)), s.call));
        final lifted = s(cv.add(s(lL.convertTo(cv.MatType.CV_32FC1)), s(cv.multiply(lift, near))));
        final merged = s(cv.merge(cv.VecMat.fromList([s(lifted.convertTo(cv.MatType.CV_8UC1)), la, lb])));
        return cv.cvtColor(merged, cv.COLOR_Lab2BGR);
      }),
    );

    // Soften skin: bilateral base (on a copy of at most 700 px) plus the
    // finest texture back. out = f + w · (smooth − f)
    final softened = t(
      _stage((s) {
        final f = s(bgr.convertTo(cv.MatType.CV_32FC3));
        // smooth = bilateral base + keep · fine texture
        final ws = math.min(1.0, 700 / long);
        final work = ws < 1
            ? s(cv.resize(bgr, (math.max(1, (w * ws).round()), math.max(1, (h * ws).round())), interpolation: cv.INTER_AREA))
            : bgr;
        var base = s(cv.bilateralFilter(work, 0, 30, math.max(2, size * ws / 40)));
        if (ws < 1) base = s(cv.resize(base, (w, h), interpolation: cv.INTER_LINEAR));
        final smooth = s(base.convertTo(cv.MatType.CV_32FC3));
        s.free(base);
        final fine = s(cv.gaussianBlur(f, (0, 0), math.max(0.6, size / 300)));
        cv.subtract(f, fine, dst: fine);
        cv.addWeighted(smooth, 1, fine, keep, 0, dst: smooth);
        s.free(fine);
        // out = f + weight · (smooth − f)
        cv.subtract(smooth, f, dst: smooth);
        final weight = s(s(cv.gaussianBlur(skin, (0, 0), math.max(1, size / 60))).convertTo(cv.MatType.CV_32FC1, alpha: soften));
        cv.multiply(smooth, _three(weight, s.call), dst: smooth);
        cv.add(f, smooth, dst: smooth);
        return smooth;
      }),
    );

    // Sharpen what isn't skin: out = s + (1 − skin) · amount · (s − blur(s)).
    return _stage((s) {
      final detail = s(cv.gaussianBlur(softened, (0, 0), math.max(0.7, size / 250)));
      cv.subtract(softened, detail, dst: detail);
      final notSkin = s(s(cv.gaussianBlur(skin, (0, 0), 2)).convertTo(cv.MatType.CV_32FC1, alpha: -sharpen, beta: sharpen));
      cv.multiply(detail, _three(notSkin, s.call), dst: detail);
      cv.add(softened, detail, dst: detail);
      return detail.convertTo(cv.MatType.CV_8UC3);
    });
  } finally {
    for (final m in tmp) {
      m.dispose();
    }
  }
}

/// Neutralises the room light's colour cast, using the wall around the
/// [person] as a grey card. Only a light, near-neutral wall counts (a
/// painted wall says little about the light). New image.
cv.Mat _wallWhiteBalance(cv.Mat bgr, cv.Mat person) {
  final (_, wall) = cv.threshold(person, 12, 255, cv.THRESH_BINARY_INV);
  final lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
  try {
    if (cv.countNonZero(wall) < 500) return bgr.clone();
    final m = cv.mean(lab, mask: wall);
    final (da, db) = (m.val2 - 128, m.val3 - 128);
    if (m.val1 < 110 || math.sqrt(da * da + db * db) > 30) return bgr.clone();
    final ch = cv.split(lab);
    final a = ch[1].convertTo(cv.MatType.CV_8UC1, beta: -0.8 * da);
    final b = ch[2].convertTo(cv.MatType.CV_8UC1, beta: -0.8 * db);
    final merged = cv.merge(cv.VecMat.fromList([ch[0], a, b]));
    final out = cv.cvtColor(merged, cv.COLOR_Lab2BGR);
    for (final x in [a, b, merged]) {
      x.dispose();
    }
    ch.dispose();
    return out;
  } finally {
    wall.dispose();
    lab.dispose();
  }
}

/// Brightens an under-exposed photo like a longer exposure: one gain on
/// linear light from the whole photo's highlights (99.5th percentile:
/// wall, shirt, eyes, teeth), with a soft shoulder so nothing clips. Never
/// from the person alone: on a well-lit photo of darker skin the brightest
/// person pixels can be skin, and that would lighten it. A per-value
/// lookup table, the same for all three channels. New image.
cv.Mat _exposure(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final hi = _toLinear(_percentile(gray, null, 0.995) / 255);
  gray.dispose();
  final gain = (0.72 / math.max(hi, 1e-3)).clamp(1.0, 1.6);
  if (gain <= 1.10) return bgr.clone();
  const knee = 0.8;
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    var x = _toLinear(v / 255) * gain;
    if (x > knee) {
      final over = x - knee;
      x = knee + over / (1 + over / (1 - knee));
    }
    lut[v] = (_toSrgb(x) * 255).round().clamp(0, 255);
  }
  final table = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, lut);
  try {
    return cv.LUT(bgr, table);
  } finally {
    table.dispose();
  }
}

double _toLinear(double x) =>
    x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();

double _toSrgb(double x) {
  final c = x.clamp(0.0, 1.0);
  return c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
}

/// The [q] quantile (0…1) of an 8-bit single-channel image, over the
/// pixels where [mask] (8-bit, same size) is above half, or all of them.
double _percentile(cv.Mat gray8, cv.Mat? mask, double q) {
  final gm = gray8.isContinuous ? gray8 : gray8.clone();
  final mm = mask == null || mask.isContinuous ? mask : mask.clone();
  final hist = List<int>.filled(256, 0);
  var n = 0;
  try {
    final g = gm.data;
    final m = mm?.data;
    for (var i = 0; i < g.length; i++) {
      if (m != null && m[i] < 128) continue;
      hist[g[i]]++;
      n++;
    }
  } finally {
    if (!identical(gm, gray8)) gm.dispose();
    if (mm != null && !identical(mm, mask)) mm.dispose();
  }
  if (n == 0) return 255;
  final target = q * n;
  var acc = 0;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc >= target) return v.toDouble();
  }
  return 255;
}

/// Puts [color] behind the person. [mask] (8-bit, 255 = person, any size)
/// is ML Kit's coarse confidence map, so on its own its edge is a soft band
/// a few pixels wide where the old wall shows through as a pale fringe.
/// Three fixes before blending:
///  1. a colour guided filter snaps the band to the photo's own edges
///     (hair, shoulders), then a tighten makes the edge crisp and keeps
///     it off the wall;
///  2. near the outline, where the wall and the person clearly differ in
///     colour, each pixel's share is read from its colour between the two
///     (a plain wall is easy to model), so a wedge of wall the mask took
///     for person still goes;
///  3. blur-fusion foreground estimation (Forte & Pitié 2021) takes the
///     wall's colour out of the edge pixels, so what is blended with
///     [color] is hair, not hair-plus-white-wall.
/// The wide averages run on a ~320 px copy and are scaled back up (they
/// are smooth); only the per-pixel steps run at full size.
cv.Mat replaceBackground(cv.Mat img, cv.Mat mask, cv.Scalar color) {
  final tmp = <cv.Mat>[];
  cv.Mat t(cv.Mat m) {
    tmp.add(m);
    return m;
  }

  void drop(cv.Mat m) {
    tmp.remove(m);
    m.dispose();
  }

  try {
    final bgr = img.channels == 1 ? t(cv.cvtColor(img, cv.COLOR_GRAY2BGR)) : img;
    final (w, h) = (bgr.cols, bgr.rows);
    final long = math.max(w, h);
    final scale = math.min(1.0, 320 / long);
    final (sw, sh) = (math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
    cv.Mat down(cv.Mat m, _Track s) => s(cv.resize(m, (sw, sh), interpolation: cv.INTER_AREA));
    cv.Mat up(cv.Mat m, _Track s) => s(cv.resize(m, (w, h), interpolation: cv.INTER_LINEAR));
    int px(double fullPx) => math.max(1, (fullPx * scale).round());

    // Full-size float images are big (a 2 MP photo: 24 MB each), so every
    // step below runs in a _stage that frees its working copies on return.
    final image = t(bgr.convertTo(cv.MatType.CV_32FC3, alpha: 1 / 255));
    final smallImage = down(image, t);
    final smallCoarse = t(down(mask, t).convertTo(cv.MatType.CV_32FC1, alpha: 1 / 255));

    // 1. Fast colour guided filter: coefficients on the small copy,
    // applied to the full-size photo. Colour, not just lightness, tells
    // brown hair from a beige wall. Then tighten: 0.3 → 0, 0.8 → 1, a
    // crisp edge (the coarse map leans generous).
    final (gA, gB) = _guidedCoefficients(smallImage, smallCoarse, px(math.max(2, long / 100)), 1e-3, t);
    final tight = t(
      _stage((s) {
        final channels = cv.split(image);
        var guided = up(gB, s.call);
        for (var c = 0; c < 3; c++) {
          guided = s(cv.add(guided, s(cv.multiply(up(gA[c], s.call), channels[c]))));
        }
        channels.dispose();
        return _clamp01(s(guided.convertTo(cv.MatType.CV_32FC1, alpha: 1 / 0.5, beta: -0.3 / 0.5)), s.call);
      }),
    );

    // 2. Colour near the outline. α = α + trust · (α_c − α), never above
    // the guided α plus a little: the colour can only take wall away, not
    // add person.
    final model = _colourModel(smallImage, smallCoarse, down(tight, t), px(long / 10), px(long / 40), t);
    final alpha = t(
      _stage((s) {
        // proj = Σ (I − B̄) · d, computed in place.
        final diff = s(cv.subtract(image, up(model.bgMean, s.call)));
        cv.multiply(diff, up(model.d, s.call), dst: diff);
        final proj = s(_sum3(diff, s.call));
        s.free(diff);
        final colour = s(_clamp01(s(cv.divide(proj, s(up(model.dist2, s.call).addF32(1e-5)))), s.call));
        final mixed = s(cv.add(tight, s(cv.multiply(up(model.trust, s.call), s(cv.subtract(colour, tight))))));
        return cv.min(mixed, s(tight.addF32(0.05)));
      }),
    );
    drop(tight);

    // 3. Blur fusion: the wide pass's averages on the small copy, the fine
    // pass at full size.
    final (smallF, smallB) = _fusionMeans(smallImage, smallImage, smallImage, down(alpha, t), px(long / 12) | 1, t);
    final fg = t(
      _stage((s) {
        final roughB = up(smallB, s.call);
        final roughF = up(smallF, s.call);
        final rough = _fusionStep(image, roughF, roughB, alpha, s.call);
        s.free(roughF);
        final (fineF, fineB) = _fusionMeans(image, rough, roughB, alpha, math.max(3, long ~/ 170) | 1, s.call);
        s
          ..free(rough)
          ..free(roughB);
        return _fusionStep(image, fineF, fineB, alpha, s.call);
      }),
    );
    drop(image);

    // out = fill + (fg · 255 − fill) · alpha
    return _stage((s) {
      final fill = s(cv.Mat.fromScalar(h, w, cv.MatType.CV_32FC3, color));
      final out = s(fg.convertTo(cv.MatType.CV_32FC3, alpha: 255));
      cv.subtract(out, fill, dst: out);
      cv.multiply(out, _three(alpha, s.call), dst: out);
      cv.add(fill, out, dst: out);
      return out.convertTo(cv.MatType.CV_8UC3);
    });
  } finally {
    for (final m in tmp) {
      m.dispose();
    }
  }
}

/// Registers a temporary [cv.Mat] for disposal; returns it.
typedef _Track = cv.Mat Function(cv.Mat m);

/// A stage's temporaries: `s(m)` registers one, [free] drops one as soon
/// as it's no longer needed.
class _Scope {
  final _mats = <cv.Mat>[];

  cv.Mat call(cv.Mat m) {
    _mats.add(m);
    return m;
  }

  void free(cv.Mat m) {
    if (_mats.remove(m)) m.dispose();
  }
}

/// Runs [body] with its own temporaries and frees all of them except the
/// one it returns, so a long chain of full-size steps never holds more
/// than one step's working copies.
cv.Mat _stage(cv.Mat Function(_Scope s) body) {
  final scope = _Scope();
  cv.Mat? out;
  try {
    return out = body(scope);
  } finally {
    for (final m in scope._mats) {
      if (!identical(m, out)) m.dispose();
    }
  }
}

cv.Mat _three(cv.Mat m, _Track s) => s(cv.merge(cv.VecMat.fromList([m, m, m])));

/// Colour guided filter coefficients (He et al. 2010): `q = Σ A_c · I_c`
/// `+ B` follows the edges of the 3-channel float [guide] within [r] px.
/// [p] single-channel float; [eps] in the guide's units squared. The 3 × 3
/// colour covariance is inverted per pixel by cofactors.
(List<cv.Mat>, cv.Mat) _guidedCoefficients(
  cv.Mat guide,
  cv.Mat p,
  int r,
  double eps,
  cv.Mat Function(cv.Mat) t,
) {
  final k = (2 * r + 1, 2 * r + 1);
  cv.Mat box(cv.Mat m) => t(cv.blur(m, k));
  cv.Mat mul(cv.Mat a, cv.Mat b) => t(cv.multiply(a, b));
  cv.Mat sub(cv.Mat a, cv.Mat b) => t(cv.subtract(a, b));
  cv.Mat add(cv.Mat a, cv.Mat b) => t(cv.add(a, b));
  final split = cv.split(guide);
  final g = [for (var c = 0; c < 3; c++) t(split[c].clone())];
  split.dispose();
  final mI = [for (final c in g) box(c)];
  final mP = box(p);
  final cov = [
    for (var c = 0; c < 3; c++) sub(box(mul(g[c], p)), mul(mI[c], mP)),
  ];
  cv.Mat v(int i, int j) {
    final m = sub(box(mul(g[i], g[j])), mul(mI[i], mI[j]));
    return i == j ? t(m.addF32(eps)) : m;
  }

  final (a11, a12, a13, a22, a23, a33) = (
    v(0, 0),
    v(0, 1),
    v(0, 2),
    v(1, 1),
    v(1, 2),
    v(2, 2),
  );
  final c11 = sub(mul(a22, a33), mul(a23, a23));
  final c12 = sub(mul(a13, a23), mul(a12, a33));
  final c13 = sub(mul(a12, a23), mul(a13, a22));
  final c22 = sub(mul(a11, a33), mul(a13, a13));
  final c23 = sub(mul(a12, a13), mul(a11, a23));
  final c33 = sub(mul(a11, a22), mul(a12, a12));
  final det = add(add(mul(a11, c11), mul(a12, c12)), mul(a13, c13));
  final inv = [
    [c11, c12, c13],
    [c12, c22, c23],
    [c13, c23, c33],
  ];
  final a = [
    for (var c = 0; c < 3; c++)
      t(
        cv.divide(
          add(
            add(mul(inv[c][0], cov[0]), mul(inv[c][1], cov[1])),
            mul(inv[c][2], cov[2]),
          ),
          det,
        ),
      ),
  ];
  var b = mP;
  for (var c = 0; c < 3; c++) {
    b = sub(b, mul(a[c], mI[c]));
  }
  return ([for (final x in a) box(x)], box(b));
}

/// Local wall colour, person − wall colour difference, its squared length,
/// and how far to trust a colour reading, from box means ([k] px) of the
/// confident pixels on each side. Trust needs the two colours far apart,
/// each side close to one colour (a white shirt beside a dark jacket is not
/// "the person's colour"), both seen nearby, and the pixel within [r] px of
/// the [coarse] outline (not inside the hair).
({cv.Mat bgMean, cv.Mat d, cv.Mat dist2, cv.Mat trust}) _colourModel(
  cv.Mat image,
  cv.Mat coarse,
  cv.Mat alpha,
  int k,
  int r,
  cv.Mat Function(cv.Mat) t,
) {
  final size = (k | 1, k | 1);
  cv.Mat box(cv.Mat m) => t(cv.blur(m, size));
  cv.Mat three(cv.Mat m) => t(cv.merge(cv.VecMat.fromList([m, m, m])));
  cv.Mat clamp(cv.Mat m, double a, double b) =>
      t(_clamp01(t(m.convertTo(cv.MatType.CV_32FC1, alpha: a, beta: b)), t));

  final (_, fgW) = cv.threshold(alpha, 0.97, 1, cv.THRESH_BINARY);
  final (_, bgW) = cv.threshold(alpha, 0.03, 1, cv.THRESH_BINARY_INV);
  t(fgW);
  t(bgW);
  final fgN = box(fgW);
  final bgN = box(bgW);
  final fgMean = t(
    cv.divide(
      box(t(cv.multiply(image, three(fgW)))),
      three(t(fgN.addF32(1e-5))),
    ),
  );
  final bgMean = t(
    cv.divide(
      box(t(cv.multiply(image, three(bgW)))),
      three(t(bgN.addF32(1e-5))),
    ),
  );
  final d = t(cv.subtract(fgMean, bgMean));
  final dist2 = t(_sum3(t(cv.multiply(d, d)), t));
  final dist = t(cv.sqrt(dist2));

  // Spread of each side: √(E|I|² − |E I|²) over the window.
  final sq = t(cv.multiply(image, image));
  cv.Mat spread(cv.Mat w, cv.Mat n, cv.Mat mean) {
    final e2 = t(
      cv.divide(
        t(_sum3(box(t(cv.multiply(sq, three(w)))), t)),
        t(n.addF32(1e-5)),
      ),
    );
    final v = t(cv.subtract(e2, t(_sum3(t(cv.multiply(mean, mean)), t))));
    final (_, pos) = cv.threshold(v, 0, 0, cv.THRESH_TOZERO);
    return t(cv.sqrt(t(pos)));
  }

  final ratio = t(
    cv.divide(
      t(cv.add(spread(fgW, fgN, fgMean), spread(bgW, bgN, bgMean))),
      t(dist.addF32(1e-5)),
    ),
  );
  final plain = clamp(ratio, -2.5, 1.5); // ≤ 0.2 trusted, ≥ 0.6 not
  final apart = clamp(dist, 1 / 0.15, -1); // ≥ 0.3 apart (≈ 75 / 255)
  final seen = t(cv.min(clamp(fgN, 10, 0), clamp(bgN, 10, 0)));
  final (_, inside) = cv.threshold(coarse, 0.5, 1, cv.THRESH_BINARY);
  t(inside);
  final kernel = t(
    cv.getStructuringElement(cv.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)),
  );
  final ring = t(
    cv.subtract(
      t(_morph(inside, cv.MORPH_DILATE, kernel)),
      t(_morph(inside, cv.MORPH_ERODE, kernel)),
    ),
  );
  final band = t(cv.gaussianBlur(ring, (0, 0), math.max(1, r / 2)));
  final trust = t(
    cv.multiply(t(cv.multiply(t(cv.multiply(apart, seen)), band)), plain),
  );
  return (bgMean: bgMean, d: d, dist2: dist2, trust: trust);
}

/// Blur-fusion box means ([k] px): F̄ = box(F·α) / box(α) and
/// B̄ = box(B·(1 − α)) / box(1 − α). Both registered with [t].
(cv.Mat, cv.Mat) _fusionMeans(cv.Mat image, cv.Mat fg, cv.Mat bg, cv.Mat alpha, int k, _Track t) {
  cv.Mat mean(cv.Mat x, cv.Mat weight) => t(
    _stage((s) {
      final w3 = _three(weight, s.call);
      final prod = s(cv.multiply(x, w3));
      s.free(w3);
      final sum = s(cv.blur(prod, (k, k)));
      s.free(prod);
      final norm = s(cv.blur(weight, (k, k)).addF32(1e-5));
      cv.divide(sum, _three(norm, s.call), dst: sum);
      return sum;
    }),
  );
  final inv = alpha.convertTo(cv.MatType.CV_32FC1, alpha: -1, beta: 1);
  try {
    return (mean(fg, alpha), mean(bg, inv));
  } finally {
    inv.dispose();
  }
}

/// F = F̄ + α (I − α F̄ − (1 − α) B̄), clamped to 0…1, computed in place
/// (three full-size copies at most). Registered with [t].
cv.Mat _fusionStep(cv.Mat image, cv.Mat blurF, cv.Mat blurB, cv.Mat alpha, _Track t) => t(
  _stage((s) {
    final a3 = _three(alpha, s.call);
    final r = s(cv.multiply(a3, blurF));
    cv.subtract(image, r, dst: r);
    final rest = _three(s(alpha.convertTo(cv.MatType.CV_32FC1, alpha: -1, beta: 1)), s.call);
    cv.multiply(rest, blurB, dst: rest);
    cv.subtract(r, rest, dst: r);
    s.free(rest);
    cv.multiply(a3, r, dst: r);
    s.free(a3);
    cv.add(blurF, r, dst: r);
    cv.threshold(r, 0, 0, cv.THRESH_TOZERO, dst: r);
    cv.threshold(r, 1, 1, cv.THRESH_TRUNC, dst: r);
    return r;
  }),
);

/// Sum of a 3-channel float image's channels.
cv.Mat _sum3(cv.Mat m, cv.Mat Function(cv.Mat) t) {
  final c = cv.split(m);
  final s = cv.add(t(cv.add(c[0], c[1])), c[2]);
  c.dispose();
  return s;
}

/// [m] clamped to 0…1 (float, any channels).
cv.Mat _clamp01(cv.Mat m, cv.Mat Function(cv.Mat) t) {
  final (_, low) = cv.threshold(m, 0, 0, cv.THRESH_TOZERO);
  t(low);
  final (_, out) = cv.threshold(low, 1, 1, cv.THRESH_TRUNC);
  return out;
}

/// Scales [img] to cover [width] × [height] (area averaging when shrinking)
/// and crops the centre: exactly that size, nothing stretched.
cv.Mat coverResize(cv.Mat img, int width, int height) {
  final s = math.max(width / img.cols, height / img.rows);
  final w = math.max(width, (img.cols * s).round());
  final h = math.max(height, (img.rows * s).round());
  final scaled = cv.resize(img, (
    w,
    h,
  ), interpolation: s < 1 ? cv.INTER_AREA : cv.INTER_CUBIC);
  final roi = scaled.region(
    cv.Rect((w - width) ~/ 2, (h - height) ~/ 2, width, height),
  );
  final out = roi.clone();
  roi.dispose();
  scaled.dispose();
  return out;
}

/// Pixel rectangle of [region] (fractions: left, top, right, bottom) in a
/// [w] × [h] image, at least 1 px and inside it.
cv.Rect _regionRect(FracRect region, int w, int h) {
  final x0 = (region.left * w).floor().clamp(0, w - 1);
  final y0 = (region.top * h).floor().clamp(0, h - 1);
  final x1 = (region.right * w).ceil().clamp(x0 + 1, w);
  final y1 = (region.bottom * h).ceil().clamp(y0 + 1, h);
  return cv.Rect(x0, y0, x1 - x0, y1 - y0);
}

/// The upright photo's [region] at most [longEdge] px as a JPEG at [out]:
/// the passport crop, segmented on its own for a sharper person mask.
/// Returns its size.
(int, int) writeRegion(String path, FracRect region, int longEdge, String out) {
  final img = readUpright(path);
  final roi = img.region(_regionRect(region, img.cols, img.rows));
  final fitted = fitLongEdge(roi, longEdge);
  try {
    File(out).parent.createSync(recursive: true);
    writeJpeg(fitted, out, quality: 92);
    return (fitted.cols, fitted.rows);
  } finally {
    // fitted is roi itself when the crop is already small enough.
    disposeUnless(fitted, roi);
    roi.dispose();
    img.dispose();
  }
}

/// A person mask for the whole upright photo that is sharp inside
/// [region]: the [base] whole-photo mask (or nothing) scaled up to the
/// region's resolution, with [data] ([width] × [height], covering exactly
/// [region]) pasted over it. At most 4096 px on the long edge.
void composeMask(
  String? base,
  Uint8List data,
  int width,
  int height,
  FracRect region,
  String out,
) {
  var cw = width / (region.right - region.left);
  var ch = height / (region.bottom - region.top);
  final k = math.min(1.0, 4096 / math.max(cw, ch));
  cw *= k;
  ch *= k;
  final (w, h) = (math.max(1, cw.round()), math.max(1, ch.round()));
  final part = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, data);
  final baseMat = base == null
      ? null
      : cv.imread(base, flags: cv.IMREAD_GRAYSCALE);
  final canvas = baseMat == null || baseMat.isEmpty
      ? cv.Mat.zeros(h, w, cv.MatType.CV_8UC1)
      : cv.resize(baseMat, (w, h), interpolation: cv.INTER_LINEAR);
  final rect = _regionRect(region, w, h);
  final sized = cv.resize(part, (
    rect.width,
    rect.height,
  ), interpolation: k < 1 ? cv.INTER_AREA : cv.INTER_LINEAR);
  final roi = canvas.region(rect);
  try {
    sized.copyTo(roi);
    File(out).parent.createSync(recursive: true);
    if (!cv.imwrite(out, canvas)) throw StateError('Could not write $out');
  } finally {
    for (final m in [roi, sized, canvas, part, ?baseMat]) {
      m.dispose();
    }
  }
}

/// Writes 8-bit gray [data] (row-major, [width] × [height]) as a PNG.
void writeGray(Uint8List data, int width, int height, String path) {
  final m = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, data);
  try {
    File(path).parent.createSync(recursive: true);
    if (!cv.imwrite(path, m)) throw StateError('Could not write $path');
  } finally {
    m.dispose();
  }
}

/// Ink colours (BGR): black #15171A, blue #1F3FAE.
cv.Scalar? _inkBgr(InkColor ink) => switch (ink) {
  InkColor.black => cv.Scalar(26, 23, 21),
  InkColor.blue => cv.Scalar(174, 63, 31),
  InkColor.original => null,
};

/// Signatures and date stamps (feature 4): each transparent PNG is fitted
/// into its rect (fractions of [page], aspect kept, centred) and alpha
/// blended. Returns [page] itself when there's nothing to draw; a grayscale
/// page becomes colour so blue ink stays blue.
cv.Mat withOverlays(cv.Mat page, List<PageOverlay> overlays) {
  if (overlays.isEmpty) return page;
  final out = page.channels == 1
      ? cv.cvtColor(page, cv.COLOR_GRAY2BGR)
      : page.clone();
  for (final o in overlays) {
    final png = cv.imread(o.imagePath, flags: cv.IMREAD_UNCHANGED);
    if (png.isEmpty || png.channels != 4) {
      png.dispose();
      continue;
    }
    final boxW = o.width * out.cols;
    final boxH = o.height * out.rows;
    final s = math.min(boxW / png.cols, boxH / png.rows);
    final w = math.max(1, (png.cols * s).round());
    final h = math.max(1, (png.rows * s).round());
    final x = (o.left * out.cols + (boxW - w) / 2)
        .round()
        .clamp(0, math.max(0, out.cols - w))
        .toInt();
    final y = (o.top * out.rows + (boxH - h) / 2)
        .round()
        .clamp(0, math.max(0, out.rows - h))
        .toInt();
    if (w > out.cols || h > out.rows) {
      png.dispose();
      continue;
    }
    final sized = cv.resize(png, (
      w,
      h,
    ), interpolation: s < 1 ? cv.INTER_AREA : cv.INTER_LINEAR);
    final ch = cv.split(sized);
    final ink = _inkBgr(o.ink);
    final color = ink == null
        ? cv.merge(cv.VecMat.fromList([ch[0], ch[1], ch[2]]))
        : cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, ink);
    final a = ch[3].convertTo(cv.MatType.CV_32FC1, alpha: 1 / 255);
    final a3 = cv.merge(cv.VecMat.fromList([a, a, a]));
    final roi = out.region(cv.Rect(x, y, w, h));
    final roiF = roi.convertTo(cv.MatType.CV_32FC3);
    final colF = color.convertTo(cv.MatType.CV_32FC3);
    final diff = cv.subtract(colF, roiF);
    final scaled = cv.multiply(diff, a3);
    final blended = cv.add(roiF, scaled);
    final back = blended.convertTo(cv.MatType.CV_8UC3);
    back.copyTo(roi);
    for (final m in [
      png,
      sized,
      color,
      a,
      a3,
      roi,
      roiF,
      colF,
      diff,
      scaled,
      blended,
      back,
    ]) {
      m.dispose();
    }
    for (final c in ch) {
      c.dispose();
    }
  }
  return out;
}

/// "Scan from paper" (feature 4): a photo of a signature on white paper →
/// transparent PNG at [out]. Grey → background normalised → Otsu → specks
/// removed → lightly smoothed alpha → trimmed to the ink with a margin. The
/// colour channels keep the photo's ink (for the Original ink option).
/// Throws [StateError] when no ink is found.
void signatureFromPhoto(String src, String out, {int maxLongEdge = 1600}) {
  final img = readUprightAtMost(src, maxLongEdge);
  final bgr = fitLongEdge(img, maxLongEdge);
  disposeUnless(img, bgr);
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final norm = _normalizeIllumination(gray, scale: 255);
  final (_, ink) = cv.threshold(
    norm,
    0,
    255,
    cv.THRESH_BINARY_INV | cv.THRESH_OTSU,
  );
  final k = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
  final clean = _morph(ink, cv.MORPH_OPEN, k);
  final alpha = cv.gaussianBlur(clean, (3, 3), 0);
  try {
    // Bounding box of the ink.
    final w = clean.cols;
    final h = clean.rows;
    final data = clean.data;
    var x0 = w;
    var y0 = h;
    var x1 = -1;
    var y1 = -1;
    var count = 0;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (data[row + x] != 0) {
          count++;
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    // Ink must be a small part of the photo, else it's not a signature on
    // paper (a dark table, a blank page that thresholded into noise).
    final share = count / (w * h);
    if (x1 < 0 || count < 150 || share > 0.25) {
      throw StateError('no signature found');
    }
    final margin = (math.max(x1 - x0, y1 - y0) * 0.04).round() + 2;
    final rx = math.max(0, x0 - margin);
    final ry = math.max(0, y0 - margin);
    final rect = cv.Rect(
      rx,
      ry,
      math.min(w, x1 + margin + 1) - rx,
      math.min(h, y1 + margin + 1) - ry,
    );
    final colorRoi = bgr.region(rect);
    final alphaRoi = alpha.region(rect);
    final ch = cv.split(colorRoi);
    final bgra = cv.merge(cv.VecMat.fromList([ch[0], ch[1], ch[2], alphaRoi]));
    File(out).parent.createSync(recursive: true);
    if (!cv.imwrite(out, bgra)) throw StateError('Could not write $out');
    for (final m in [colorRoi, alphaRoi, bgra, ...ch]) {
      m.dispose();
    }
  } finally {
    for (final m in [bgr, gray, norm, ink, k, clean, alpha]) {
      m.dispose();
    }
  }
}

/// One card side for print (P1-9): from the original, cropped and warped to
/// the real card shape, filtered, then shrunk with area averaging to the
/// pixel size for [dpi] at [widthMm] × [heightMm] — never above the photo's
/// own resolution. Always landscape (portrait renders are turned).
///
/// The filter runs on at most 2× the print size (it used to run on the
/// whole camera image, seconds per side on a mid-range phone).
cv.Mat renderCard(
  String originalPath,
  PageEdits edits, {
  required double widthMm,
  required double heightMm,
  required int dpi,
  StepTimer? timer,
}) {
  final tw = (widthMm / 25.4 * dpi).round();
  final th = (heightMm / 25.4 * dpi).round();
  final full = renderEdits(originalPath, edits, maxLongEdge: 2 * math.max(tw, th), timer: timer);
  return _toCardSize(full, tw, th, timer);
}

/// Landscape, then INTER_AREA down to [tw] × [th] (never enlarged). Takes
/// ownership of [full].
cv.Mat _toCardSize(cv.Mat full, int tw, int th, StepTimer? timer) {
  var card = full;
  if (card.rows > card.cols) {
    card = cv.rotate(full, cv.ROTATE_90_COUNTERCLOCKWISE);
    full.dispose();
  }
  if (card.cols <= tw) return card; // native resolution is lower: keep it
  final out = cv.resize(card, (tw, th), interpolation: cv.INTER_AREA);
  card.dispose();
  timer?.lap('resize to $tw×$th');
  return out;
}

/// A passport photo (feature 5) for print: the framed crop, filtered and
/// shrunk to [widthMm] × [heightMm] at [dpi]. Never enlarged and never
/// turned (unlike a card side).
cv.Mat renderSized(
  String originalPath,
  PageEdits edits, {
  required double widthMm,
  required double heightMm,
  required int dpi,
}) {
  final tw = (widthMm / 25.4 * dpi).round();
  final th = (heightMm / 25.4 * dpi).round();
  // Crop straight to about the print size: no full-resolution copy.
  final full = renderEdits(originalPath, edits, maxLongEdge: math.max(tw, th));
  if (full.cols <= tw) return full;
  final out = cv.resize(full, (tw, th), interpolation: cv.INTER_AREA);
  full.dispose();
  return out;
}

/// Dedicated OCR image: crop + rotate at full resolution, then the
/// reference `ocr_image()`. Never the user's chosen filter.
cv.Mat renderForOcr(String path, PageEdits edits) {
  final img = readUpright(path);
  final cropped = cropAndRotate(img, edits);
  disposeUnless(img, cropped);
  final out = ocrImage(cropped);
  cropped.dispose();
  return out;
}

class IngestReport {
  const IngestReport({
    required this.detection,
    required this.sharpness,
    required this.brightness,
    required this.width,
    required this.height,
    required this.decodeScale,
    required this.orientation,
    this.cardSharpness,
    this.blurryCells = const [],
  });

  final DetectionReport detection;

  /// Document camera shots (round 6, P1-1): the 3 × 3 cells of the page
  /// much blurrier than its sharpest part ([blurryRegions]).
  final List<(int, int)> blurryCells;

  /// The `[orient]` line from [normalizeCapture] (P0-1).
  final String orientation;

  /// ID / passport only (P0-2): Laplacian variance of the warped card at
  /// 1000 px wide — the card itself, not the table around it.
  final double? cardSharpness;

  /// Laplacian variance on a 1000 px copy; low = blurry.
  final double sharpness;

  /// Mean gray level 0..255; low = dark.
  final double brightness;

  /// Original pixel size (upright), from the JPEG header when available.
  final int width;
  final int height;

  /// 1 = full decode, 2 / 4 / 8 = reduced decode (big photo or low memory).
  final int decodeScale;
}

/// Ingest: one decode per captured / imported photo. The original file is
/// NOT touched (no re-encode, no downscale); this writes the editor's
/// preview, detects the document on it and measures sharpness / brightness.
///
/// Decodes at 1/2 – 1/8 scale when the photo is much larger than the preview,
/// and retries at a smaller scale if decoding fails (low memory) instead of
/// failing the scan.
IngestReport ingest({
  required String src,
  required String previewOut,
  required int previewLongEdge,
  double? aspectHint,
  ({double left, double top, double right, double bottom})? searchArea,
  CaptureMeta? capture,
}) {
  // P0-1: make the original upright once (EXIF, sensor, how it was held),
  // and no larger than 3000 px (round 6, P0-3).
  final orientation = normalizeCapture(src, capture, maxLongEdge: scanMaxLongEdge);
  final header = jpegSize(src);
  final (img, scale) = _decodeForPreview(src, previewLongEdge, header);
  final preview = fitLongEdge(img, previewLongEdge);
  try {
    File(previewOut).parent.createSync(recursive: true);
    writeJpeg(preview, previewOut, quality: 85);
    final detection = detectDocument(
      preview,
      aspectHint: aspectHint,
      searchArea: searchArea,
    );
    final stats = captureStats(preview);
    double? cardSharpness;
    if (aspectHint != null) {
      final area = searchArea;
      final quad =
          detection.quad ??
          (area == null
              ? null
              : Quad(
                  tl: Pt(area.left, area.top),
                  tr: Pt(area.right, area.top),
                  br: Pt(area.right, area.bottom),
                  bl: Pt(area.left, area.bottom),
                ));
      if (quad != null) cardSharpness = cardSharpnessOf(img, quad, aspectHint);
    }
    // Round 6, P1-1: a document shot whose page is sharp on one side and
    // smeared on the other (the phone moved). Camera shots only; cards'
    // smooth photo areas would look "blurry".
    var blurryCells = const <(int, int)>[];
    final found = detection.quad;
    if (aspectHint == null && capture != null && found != null) {
      final page = warpToQuad(preview, found);
      blurryCells = blurryRegions(page);
      page.dispose();
    }
    // EXIF may swap the header's width and height; the decoded image is
    // upright, so take the orientation from it.
    final long = header == null
        ? math.max(img.cols, img.rows) * scale
        : math.max(header.width, header.height);
    final short = header == null
        ? math.min(img.cols, img.rows) * scale
        : math.min(header.width, header.height);
    final landscape = img.cols >= img.rows;
    return IngestReport(
      detection: detection,
      sharpness: stats.sharpness,
      brightness: stats.brightness,
      width: landscape ? long : short,
      height: landscape ? short : long,
      decodeScale: scale,
      orientation: orientation,
      cardSharpness: cardSharpness,
      blurryCells: blurryCells,
    );
  } finally {
    disposeUnless(preview, img);
    img.dispose();
  }
}

(cv.Mat, int) _decodeForPreview(
  String src,
  int target,
  ({int width, int height})? header,
) {
  const flagsByScale = {
    1: cv.IMREAD_COLOR,
    2: cv.IMREAD_REDUCED_COLOR_2,
    4: cv.IMREAD_REDUCED_COLOR_4,
    8: cv.IMREAD_REDUCED_COLOR_8,
  };
  var scale = 1;
  if (header != null) {
    final long = math.max(header.width, header.height);
    while (scale < 8 && long / (scale * 2) >= target) {
      scale *= 2;
    }
  }
  Object? lastError;
  for (var s = scale; s <= 8; s *= 2) {
    try {
      return (readUpright(src, flags: flagsByScale[s]!), s);
    } catch (e) {
      lastError = e; // out of memory or a partial file: try smaller
    }
  }
  throw StateError('Could not decode $src: $lastError');
}

/// Enhance preview without sliders (those are applied live in the UI).
///
/// The cropped + rotated page at preview size is cached at [workPath], so
/// switching filters decodes a ~1600 px image instead of the 12 MP original.
/// The [autoFilter] result (the slow part: its denoise) is cached losslessly
/// at [autoBasePath], so Auto, Colour Boost and Grayscale share one.
cv.Mat renderLook(
  String originalPath,
  PageEdits edits, {
  required String workPath,
  required int previewLongEdge,
  String? autoBasePath,
  StepTimer? timer,
}) {
  final work = _workImage(originalPath, edits, workPath, previewLongEdge, timer);
  try {
    if (autoBasePath == null || !usesAutoBase(edits.filter)) {
      final out = applyFilter(work, edits.filter);
      timer?.lap('filter ${edits.filter.name}');
      return out;
    }
    final auto = _autoBase(work, autoBasePath, timer);
    final out = switch (edits.filter) {
      FilterType.colorBoost => colorBoostFrom(auto),
      FilterType.grayscale => grayscaleFrom(auto),
      _ => auto,
    };
    disposeUnless(auto, out);
    timer?.lap('filter ${edits.filter.name} from auto base');
    return out;
  } finally {
    work.dispose();
  }
}

/// The page cropped and turned at preview size, cached at [workPath].
cv.Mat _workImage(
  String originalPath,
  PageEdits edits,
  String workPath,
  int previewLongEdge,
  StepTimer? timer,
) {
  if (File(workPath).existsSync()) {
    final work = readUpright(workPath);
    timer?.lap('load work image ${work.cols}×${work.rows} (cached)');
    return work;
  }
  final img = readUprightForCrop(originalPath, edits.crop, previewLongEdge);
  timer?.lap('decode original ${img.cols}×${img.rows}');
  final cropped = cropAndRotate(img, edits, maxLongEdge: previewLongEdge);
  final cv.Mat work;
  if (identical(cropped, img)) {
    work = img;
  } else {
    img.dispose();
    work = cropped;
  }
  timer?.lap('crop to ${work.cols}×${work.rows}');
  File(workPath).parent.createSync(recursive: true);
  writeJpeg(work, workPath, quality: 92);
  timer?.lap('save work image');
  return work;
}

/// Round 6, P0-2: Enhance's first image, before the page's cleaned base is
/// ready. The work image with the reference's instant bilateral clean-up
/// ([denoisePreview]) and the filter. Never the raw photo (except for the
/// `original` filter, which is the raw page by definition).
cv.Mat renderInstantLook(
  String originalPath,
  PageEdits edits, {
  required String workPath,
  required int previewLongEdge,
  StepTimer? timer,
}) {
  final work = _workImage(originalPath, edits, workPath, previewLongEdge, timer);
  if (edits.filter == FilterType.original) return work;
  final quick = denoisePreview(work);
  work.dispose();
  timer?.lap('quick clean-up');
  final out = applyFilterFromClean(quick, edits.filter);
  quick.dispose();
  timer?.lap('filter ${edits.filter.name}');
  return out;
}

/// Round 6, P0-2: Enhance's image once the cleaned base exists, from its
/// preview-size copy ([cleanPreviewPath]). The Auto result is cached at
/// [autoPath], so Colour Boost and Grayscale only add their last step.
cv.Mat renderLookFromClean(
  String cleanPreviewPath,
  PageEdits edits, {
  String? autoPath,
  StepTimer? timer,
}) {
  final clean = cv.imread(cleanPreviewPath, flags: cv.IMREAD_COLOR);
  if (clean.isEmpty) {
    clean.dispose();
    throw StateError('Could not read $cleanPreviewPath');
  }
  timer?.lap('load cleaned preview ${clean.cols}×${clean.rows}');
  try {
    if (autoPath == null || !usesAutoBase(edits.filter)) {
      final out = applyFilterFromClean(clean, edits.filter);
      timer?.lap('filter ${edits.filter.name}');
      return out;
    }
    final auto = _autoBase(clean, autoPath, timer, cleaned: true);
    final out = switch (edits.filter) {
      FilterType.colorBoost => colorBoostFrom(auto),
      FilterType.grayscale => grayscaleFrom(auto),
      _ => auto,
    };
    disposeUnless(auto, out);
    timer?.lap('filter ${edits.filter.name} from auto');
    return out;
  } finally {
    clean.dispose();
  }
}

/// [autoFilter] of [work] ([autoFrom] when [cleaned]), read from [path] if
/// an earlier look wrote it.
cv.Mat _autoBase(cv.Mat work, String path, StepTimer? timer, {bool cleaned = false}) {
  if (File(path).existsSync()) {
    final m = cv.imread(path, flags: cv.IMREAD_COLOR);
    if (!m.isEmpty) {
      timer?.lap('load auto base (cached)');
      return m;
    }
    m.dispose();
  }
  final auto = cleaned ? autoFrom(work) : autoFilter(work);
  timer?.lap(cleaned ? 'auto' : 'auto base (denoise)');
  // Lossless and fast to write; renamed so a half-written file is never read.
  final tmp = '$path.part.png';
  final params = cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]);
  try {
    if (cv.imwrite(tmp, auto, params: params)) File(tmp).renameSync(path);
  } finally {
    params.dispose();
  }
  timer?.lap('save auto base');
  return auto;
}

/// Viewer caches in one decode: the processed page at [previewLongEdge] and
/// a thumbnail derived from it.
void renderPageCaches(
  String originalPath,
  PageEdits edits, {
  required String processedOut,
  required String thumbOut,
  required int previewLongEdge,
  required int thumbLongEdge,
}) {
  final out = renderEdits(originalPath, edits, maxLongEdge: previewLongEdge);
  final thumb = fitLongEdge(out, thumbLongEdge);
  try {
    File(processedOut).parent.createSync(recursive: true);
    writeJpeg(out, processedOut, quality: 90);
    File(thumbOut).parent.createSync(recursive: true);
    writeJpeg(thumb, thumbOut, quality: 80);
  } finally {
    disposeUnless(thumb, out);
    out.dispose();
  }
}

/// Writes JPEG (quality) or PNG, chosen by the file extension.
void writeJpeg(cv.Mat img, String path, {int quality = 90}) {
  final isPng = path.toLowerCase().endsWith('.png');
  final params = cv.VecI32.fromList(
    isPng
        ? [cv.IMWRITE_PNG_COMPRESSION, 3]
        : [cv.IMWRITE_JPEG_QUALITY, quality],
  );
  final ok = cv.imwrite(path, img, params: params);
  params.dispose();
  if (!ok) throw StateError('Could not write $path');
}
