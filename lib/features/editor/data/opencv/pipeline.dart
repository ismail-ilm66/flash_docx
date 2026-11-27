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
import 'package:flash_dox/features/export/domain/entities/page_footer.dart';
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
///
/// [imported] (gallery, Files, share-in; round 11, P0-5): a page needs paper
/// on 2 sides of the image, not 3, to count as already filling it. With
/// [fillsFrame] false that check is skipped (snap targets want real lines).
DetectionReport detectDocument(
  cv.Mat bgr, {
  double? aspectHint,
  ({double left, double top, double right, double bottom})? searchArea,
  bool imported = false,
  bool fillsFrame = true,
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
  final r = _detect(bgr, aspectHint, imported: imported, fillsFrame: fillsFrame);
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

DetectionReport _detect(cv.Mat bgr, double? target, {bool imported = false, bool fillsFrame = true}) {
  final hFull = bgr.rows;
  final wFull = bgr.cols;
  // Round 11, P0-5: a page that already fills the photo (an import cropped
  // before, or a page shot close up). Detection would only find lines
  // inside it (a header box, a table) and crop wrongly.
  if (target == null && fillsFrame && pageFillsFrame(bgr, imported: imported)) {
    final full = Quad.full();
    return DetectionReport(
      quad: full,
      score: 1,
      elapsed: Duration.zero,
      strategy: 'fills-frame',
      candidates: 1,
      ranked: [full],
    );
  }
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
  final hi = small.rows;
  final wi = small.cols;
  final h = hi.toDouble();
  final w = wi.toDouble();
  final imgArea = h * w;

  // Gradients for the edge support check (on the blurred grey copy).
  final gray8 = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final grayBlur = cv.gaussianBlur(gray8, (5, 5), 0);
  gray8.dispose();
  final grayF = grayBlur.convertTo(cv.MatType.CV_32FC1);
  final gxM = cv.sobel(grayF, cv.MatType.CV_32F, 1, 0);
  final gyM = cv.sobel(grayF, cv.MatType.CV_32F, 0, 1);
  final magM = cv.magnitude(gxM, gyM);
  final grads = (gx: _floats(gxM), gy: _floats(gyM), mag: _floats(magM), w: wi, h: hi);
  // Once per photo, on every 4th row and column (round 11c).
  final magThr = math.max(12.0, _percentileOf(_subList(grads.mag, wi, hi), 75));
  for (final m in [grayF, gxM, gyM, magM]) {
    m.dispose();
  }
  final smallBlur = cv.gaussianBlur(small, (5, 5), 0);
  final labSmall = cv.cvtColor(smallBlur, cv.COLOR_BGR2Lab);
  smallBlur.dispose();
  final labData = Uint8List.fromList(labSmall.data);
  labSmall.dispose();

  final maps = _candidateMaps(small);
  small.dispose();
  final found = <_Candidate>[];
  final qm = cv.Mat.zeros(hi, wi, cv.MatType.CV_8UC1);
  final both = cv.Mat.zeros(hi, wi, cv.MatType.CV_8UC1);
  // Share of the quad [q] that [area] covers.
  double coverOf(List<XY> q, cv.Mat area) {
    qm.setTo(cv.Scalar.all(0));
    final pts = cv.VecVecPoint.fromList([
      [for (final p in q) cv.Point(p.x.toInt(), p.y.toInt())],
    ]);
    cv.fillPoly(qm, pts, cv.Scalar.all(255));
    pts.dispose();
    cv.bitwiseAND(qm, area, dst: both);
    return cv.countNonZero(both) / math.max(1.0, cv.countNonZero(qm).toDouble());
  }

  int onBorderOf(List<XY> q) {
    final m = 0.02 * math.max(w, h);
    return q.where((p) => p.x < m || p.y < m || p.x > w - 1 - m || p.y > h - 1 - m).length;
  }

  double aspectFactor(List<XY> q) =>
      target == null ? 1 : math.max(0.05, 1.0 - (quadAspect(q) - target).abs() / target * 2.5);

  // Round 11, P0-6: quads from the longest straight lines, scored against
  // the paper-like area (bright OR pale): a white page on a pale folder.
  final byName = {for (final (n, m) in maps) n: m};
  final paper = cv.bitwiseOR(byName['bright']!, byName['lowsat']!);
  for (final raw in _houghQuads(grayBlur, wi, hi)) {
    final q = orderCorners(raw);
    final frac = _polyArea(q) / imgArea;
    if (frac > 0.98 || frac < kMinAreaFrac) continue;
    final rect = cornerAnglesScore(q);
    if (rect < 0.55) continue;
    final cover = coverOf(q, paper);
    final pre = math.sqrt(frac) * rect * cover * cover * aspectFactor(q);
    found.add((pre: pre, q: q, onBorder: onBorderOf(q), frac: frac, src: 'hough/lines'));
  }
  paper.dispose();
  grayBlur.dispose();

  for (final (name, map) in maps) {
    final retr = name == 'edges' ? cv.RETR_LIST : cv.RETR_EXTERNAL;
    final (contours, hierarchy) = cv.findContours(map, retr, cv.CHAIN_APPROX_SIMPLE);
    for (var i = 0; i < contours.length; i++) {
      final c = contours[i];
      final area = cv.contourArea(c);
      if (area < kMinAreaFrac * imgArea) continue;
      final cands = <(String, List<XY>)>[];
      final q0 = _quadFromContour(c);
      if (q0 != null) cands.add(('hull', q0));
      // A region merged with something else (another sheet, a pale table
      // corner): also quads from straight stretches of its outline.
      if (name != 'edges') {
        for (final qq in _lineQuads(c, wi, hi)) {
          cands.add(('lines', qq));
        }
      }
      if (cands.isEmpty) continue;
      final region = cv.Mat.zeros(hi, wi, cv.MatType.CV_8UC1);
      cv.drawContours(region, contours, i, cv.Scalar.all(255), thickness: -1);
      for (final (kind, raw) in cands) {
        var q = orderCorners(raw);
        if (name != 'edges' && kind == 'hull') {
          // Round 8: no longer pushed 2 % outward (it pulled table into the
          // crop); still clipped to the photo like the reference.
          q = [for (final p in q) (x: p.x.clamp(0.0, w - 1), y: p.y.clamp(0.0, h - 1))];
        }
        final qa = _polyArea(q);
        final frac = qa / imgArea;
        if (frac > 0.98 || frac < kMinAreaFrac) continue;
        final onBorder = onBorderOf(q);
        final rect = cornerAnglesScore(q);
        if (rect < 0.55) continue;
        final cover = name == 'edges' ? math.min(1.0, area / math.max(1.0, qa)) : coverOf(q, region);
        var pre = math.sqrt(frac) * rect * cover * cover;
        // The edge map has an artificial border line.
        if (name == 'edges') pre *= math.pow(0.45, onBorder).toDouble();
        pre *= aspectFactor(q);
        found.add((pre: pre, q: q, onBorder: onBorder, frac: frac, src: '$name/$kind'));
      }
      region.dispose();
    }
    contours.dispose();
    hierarchy.dispose();
    map.dispose();
  }
  qm.dispose();
  both.dispose();

  // Edge support is the expensive part: only the 16 best candidates.
  final order = List.generate(found.length, (i) => i)
    ..sort((a, b) {
      final c = found[b].pre.compareTo(found[a].pre);
      return c != 0 ? c : a - b; // stable, like Python's sorted
    });
  final scored = <({List<XY> q, double score, String src})>[];
  for (final i in order.take(16)) {
    final f = found[i];
    final sup = _edgeSupport(f.q, grads, magThr);
    // 3+ corners on the border is usually the photo frame itself: keep it
    // only when clearly smaller AND its outline follows real edges.
    if (f.onBorder >= 3 && (f.frac > 0.90 || sup.mean < 0.45)) continue;
    var score = f.pre * (0.25 + 0.75 * sup.mean) * (0.6 + 0.4 * sup.min);
    // Straight-line quads must also separate paper from something else.
    if (f.src.startsWith('hough')) score *= 0.3 + 0.7 * _sideContrast(f.q, labData, wi, hi);
    scored.add((q: f.q, score: score, src: f.src));
  }

  if (scored.isEmpty) {
    return DetectionReport(
      quad: null,
      score: 0,
      elapsed: Duration.zero,
      strategy: 'none',
      candidates: found.length,
    );
  }
  // The first candidate with the top score wins, as in the reference.
  var best = scored.first;
  for (final s in scored) {
    if (s.score > best.score) best = s;
  }
  final ranked = [...scored]..sort((a, b) => b.score.compareTo(a.score));
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
    candidates: found.length,
    ranked: ranked.take(5).map((s) => norm(s.q)).toList(),
  );
}

typedef _Candidate = ({double pre, List<XY> q, int onBorder, double frac, String src});

typedef _Grads = ({Float32List gx, Float32List gy, Float32List mag, int w, int h});

/// Reference `page_fills_frame` (round 11, P0-5): the page already fills
/// the photo when 60 %+ of a 3 % strip along a side is paper (bright,
/// > 72 % of the 90th-percentile brightness, and unsaturated, S < 60) on
/// 2 sides for imports, 3 for camera photos.
bool pageFillsFrame(cv.Mat bgr, {bool imported = false}) {
  final s = 800.0 / math.max(bgr.rows, bgr.cols);
  final im = s < 1 ? cv.resize(bgr, (0, 0), fx: s, fy: s, interpolation: cv.INTER_AREA) : bgr;
  final hsv = cv.cvtColor(im, cv.COLOR_BGR2HSV);
  if (!identical(im, bgr)) im.dispose();
  final h = hsv.rows;
  final w = hsv.cols;
  final ch = cv.split(hsv);
  hsv.dispose();
  try {
    final vLim = 0.72 * _pct8(_sub8(ch[2]), 90);
    final v = ch[2].data;
    final sat = ch[1].data;
    bool isPaper(int i) => v[i] > vLim && sat[i] < 60;
    final b = math.max(3, (0.03 * math.min(h, w)).toInt());
    double strip(int x0, int x1, int y0, int y1) {
      var n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          if (isPaper(y * w + x)) n++;
        }
      }
      return n / ((x1 - x0) * (y1 - y0));
    }

    final sides = [strip(0, w, 0, b), strip(0, w, h - b, h), strip(0, b, 0, h), strip(w - b, w, 0, h)];
    return sides.where((p) => p >= 0.6).length >= (imported ? 2 : 3);
  } finally {
    ch.dispose();
  }
}

/// Reference `detect_live` (round 11b, P0-15): the same detector as a
/// photo on a small camera frame (scaled to [liveSize] long side if it is
/// bigger). Normalised corners, or null.
Quad? detectLive(cv.Mat smallBgr, {int liveSize = 320}) {
  final long = math.max(smallBgr.rows, smallBgr.cols);
  final m = long > liveSize + 8
      ? cv.resize(smallBgr, (smallBgr.cols * liveSize ~/ long, smallBgr.rows * liveSize ~/ long), interpolation: cv.INTER_AREA)
      : smallBgr;
  try {
    final r = detectDocument(m);
    if (r.quad == null || r.score <= 0) return null;
    return r.quad;
  } finally {
    disposeUnless(m, smallBgr);
  }
}

/// numpy's `round` (half to even), which the reference uses for pixel
/// positions.
int _roundHalfEven(double v) {
  final f = v.floorToDouble();
  final d = v - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

/// `np.linspace(a, b, n)`.
List<double> _linspace(double a, double b, int n) {
  final step = (b - a) / (n - 1);
  return [for (var i = 0; i < n; i++) i == n - 1 ? b : a + i * step];
}

/// Reference `_edge_support`: how much of the quad's outline lies on a real
/// edge. Per side, 40 points (corners skipped) look up to 3 px across the
/// side for a strong gradient pointing across it. (mean, min) of the four
/// sides, 0..1: a side along the photo border or across a table gets ~0, a
/// real page edge ~0.6–1.
({double mean, double min}) _edgeSupport(List<XY> q, _Grads g, double thr) {
  final sides = <double>[];
  for (var i = 0; i < 4; i++) {
    final a = q[i];
    final b = q[(i + 1) % 4];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 8) {
      sides.add(0);
      continue;
    }
    final nx = -dy / len;
    final ny = dx / len;
    var hits = 0;
    var tot = 0;
    for (final f in _linspace(0.08, 0.92, 40)) {
      final px = a.x + dx * f;
      final py = a.y + dy * f;
      tot++;
      for (final off in const [0, -1, 1, -2, 2, -3, 3]) {
        final x = _roundHalfEven(px + nx * off);
        final y = _roundHalfEven(py + ny * off);
        if (x < 0 || x >= g.w || y < 0 || y >= g.h) continue;
        final k = y * g.w + x;
        final m = g.mag[k];
        if (m > thr && ((g.gx[k] * nx + g.gy[k] * ny) / (m + 1e-6)).abs() > 0.75) {
          hits++;
          break;
        }
      }
    }
    sides.add(hits / math.max(1, tot));
  }
  return (mean: sides.reduce((a, b) => a + b) / 4, min: sides.reduce(math.min));
}

/// OpenCV's `isContourConvex` on float points: every turn the same way
/// (a straight or reversed turn is not convex).
bool _isConvex(List<XY> p) {
  final n = p.length;
  var prev = p[(n - 2 + n) % n];
  var cur = p[n - 1];
  var dx0 = cur.x - prev.x;
  var dy0 = cur.y - prev.y;
  var orientation = 0;
  for (var i = 0; i < n; i++) {
    prev = cur;
    cur = p[i];
    final dx = cur.x - prev.x;
    final dy = cur.y - prev.y;
    final dxdy0 = dx * dy0;
    final dydx0 = dy * dx0;
    orientation |= dydx0 > dxdy0 ? 1 : (dydx0 < dxdy0 ? 2 : 3);
    if (orientation == 3) return false;
    dx0 = dx;
    dy0 = dy;
  }
  return true;
}

/// Where the lines through segments [s1] and [s2] meet, or null if parallel.
XY? _lineIntersection((XY, XY) s1, (XY, XY) s2) {
  final (p, p2) = s1;
  final (q, q2) = s2;
  final rx = p2.x - p.x;
  final ry = p2.y - p.y;
  final tx = q2.x - q.x;
  final ty = q2.y - q.y;
  final den = rx * ty - ry * tx;
  if (den.abs() < 1e-6) return null;
  final u = ((q.x - p.x) * ty - (q.y - p.y) * tx) / den;
  return (x: p.x + u * rx, y: p.y + u * ry);
}

/// The corners where 4 lines meet in turn, when all lie within 4 % of the
/// photo and form a convex quad; clipped to the photo.
List<XY>? _quadFromLines(List<(XY, XY)> lines, int w, int h) {
  final mx = 0.04 * w;
  final my = 0.04 * h;
  final pts = <XY>[];
  for (var k = 0; k < 4; k++) {
    final pt = _lineIntersection(lines[k], lines[(k + 1) % 4]);
    if (pt == null || pt.x < -mx || pt.x > w - 1 + mx || pt.y < -my || pt.y > h - 1 + my) return null;
    pts.add(pt);
  }
  if (!_isConvex(pts)) return null;
  return [for (final p in pts) (x: p.x.clamp(0.0, w - 1.0), y: p.y.clamp(0.0, h - 1.0))];
}

/// Every way to pick [k] of [n] indices, in Python's `combinations` order.
Iterable<List<int>> _combinations(int n, int k) sync* {
  if (k > n) return;
  final idx = List.generate(k, (i) => i);
  while (true) {
    yield List.of(idx);
    var i = k - 1;
    while (i >= 0 && idx[i] == i + n - k) {
      i--;
    }
    if (i < 0) return;
    idx[i]++;
    for (var j = i + 1; j < k; j++) {
      idx[j] = idx[j - 1] + 1;
    }
  }
}

/// Reference `_line_quads`: quads from 4 straight stretches of a region's
/// outline, extended until they meet. Finds the page when its region has
/// merged with another sheet behind it (one corner hidden).
List<List<XY>> _lineQuads(cv.VecPoint c, int w, int h, {int maxLines = 9}) {
  final peri = cv.arcLength(c, true);
  final approx = cv.approxPolyDP(c, 0.01 * peri, true);
  final poly = [for (var i = 0; i < approx.length; i++) (x: approx[i].x.toDouble(), y: approx[i].y.toDouble())];
  approx.dispose();
  final n = poly.length;
  if (n < 4) return const [];
  final minLen = 0.10 * math.min(w, h);
  final segs = <(int, (XY, XY), double)>[];
  for (var i = 0; i < n; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % n];
    final len = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    if (len >= minLen) segs.add((i, (a, b), len));
  }
  // Longest first (stable), at most [maxLines], back in outline order.
  final longest = List.generate(segs.length, (i) => i)
    ..sort((a, b) {
      final c = segs[b].$3.compareTo(segs[a].$3);
      return c != 0 ? c : a - b;
    });
  final kept = [for (final i in longest.take(maxLines)) segs[i]]..sort((a, b) => a.$1 - b.$1);
  if (kept.length < 4) return const [];
  return [
    for (final combo in _combinations(kept.length, 4))
      ?_quadFromLines([for (final k in combo) kept[k].$2], w, h),
  ];
}

/// Reference `_hough_quads` (round 11, P0-6): quads from the longest
/// straight lines in the photo, 2 roughly horizontal + 2 roughly vertical,
/// extended until they meet. Finds a white page on a pale folder, where
/// every brightness / colour map merges the two.
List<List<XY>> _houghQuads(cv.Mat grayU8, int w, int h, {int maxPerGroup = 6}) {
  final edges = cv.canny(grayU8, 40, 120);
  final raw = cv.HoughLinesP(edges, 1, math.pi / 180, 60, minLineLength: (0.25 * math.min(w, h)).toInt().toDouble(), maxLineGap: 15);
  edges.dispose();
  try {
    if (raw.isEmpty) return const [];
    final data = raw.isContinuous ? raw.data : raw.clone().data;
    final ints = data.buffer.asInt32List(data.offsetInBytes, raw.rows * 4);
    final hor = <((XY, XY), double)>[];
    final ver = <((XY, XY), double)>[];
    for (var i = 0; i < raw.rows; i++) {
      final x1 = ints[i * 4].toDouble();
      final y1 = ints[i * 4 + 1].toDouble();
      final x2 = ints[i * 4 + 2].toDouble();
      final y2 = ints[i * 4 + 3].toDouble();
      final ang = math.atan2(y2 - y1, x2 - x1) * 180 / math.pi % 180;
      final seg = (((x: x1, y: y1), (x: x2, y: y2)), math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)));
      if (ang < 35 || ang > 145) {
        hor.add(seg);
      } else if (ang > 55 && ang < 125) {
        ver.add(seg);
      }
    }
    // The longest line of each "track" (lines within 2 % are the same edge).
    List<(XY, XY)> merge(List<((XY, XY), double)> group, {required bool horizontal}) {
      final order = List.generate(group.length, (i) => i)
        ..sort((a, b) {
          final c = group[b].$2.compareTo(group[a].$2);
          return c != 0 ? c : a - b;
        });
      double pos((XY, XY) s) => horizontal ? (s.$1.y + s.$2.y) / 2 : (s.$1.x + s.$2.x) / 2;
      final tol = 0.02 * (horizontal ? h : w);
      final out = <(XY, XY)>[];
      for (final i in order) {
        final g = group[i].$1;
        if (out.every((o) => (pos(g) - pos(o)).abs() > tol)) out.add(g);
        if (out.length >= maxPerGroup) break;
      }
      return out;
    }

    final hs = merge(hor, horizontal: true);
    final vs = merge(ver, horizontal: false);
    if (hs.length < 2 || vs.length < 2) return const [];
    final out = <List<XY>>[];
    for (final hp in _combinations(hs.length, 2)) {
      final t1 = hs[hp[0]];
      final t2 = hs[hp[1]];
      final (top, bot) = (t1.$1.y + t1.$2.y) < (t2.$1.y + t2.$2.y) ? (t1, t2) : (t2, t1);
      for (final vp in _combinations(vs.length, 2)) {
        final v1 = vs[vp[0]];
        final v2 = vs[vp[1]];
        final (lef, rig) = (v1.$1.x + v1.$2.x) < (v2.$1.x + v2.$2.x) ? (v1, v2) : (v2, v1);
        final q = _quadFromLines([top, rig, bot, lef], w, h);
        if (q != null) out.add(q);
      }
    }
    return out;
  } finally {
    raw.dispose();
  }
}

/// Reference `_side_contrast` (round 11, P0-6): mean Lab colour difference
/// (0..1 after /20) between just inside and just outside the quad's sides.
/// A real page edge separates paper from something else; a printed rule
/// inside the page has paper on both sides. [lab] is the blurred small
/// photo in 8-bit Lab, interleaved.
double _sideContrast(List<XY> q, Uint8List lab, int w, int h, {int off = 8}) {
  final cx = (q[0].x + q[1].x + q[2].x + q[3].x) / 4;
  final cy = (q[0].y + q[1].y + q[2].y + q[3].y) / 4;
  final vals = <double>[];
  for (var i = 0; i < 4; i++) {
    final a = q[i];
    final b = q[(i + 1) % 4];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 8) {
      vals.add(0);
      continue;
    }
    var nx = -dy / len;
    var ny = dx / len;
    // Make n point inwards.
    if ((cx - (a.x + b.x) / 2) * nx + (cy - (a.y + b.y) / 2) * ny < 0) {
      nx = -nx;
      ny = -ny;
    }
    final des = <double>[];
    for (final f in _linspace(0.1, 0.9, 25)) {
      final px = a.x + dx * f;
      final py = a.y + dy * f;
      final xi = (px + nx * off).toInt();
      final yi = (py + ny * off).toInt();
      final xo = (px - nx * off).toInt();
      final yo = (py - ny * off).toInt();
      if (xi < 0 || xi >= w || yi < 0 || yi >= h || xo < 0 || xo >= w || yo < 0 || yo >= h) continue;
      final ki = (yi * w + xi) * 3;
      final ko = (yo * w + xo) * 3;
      var sum = 0.0;
      for (var c = 0; c < 3; c++) {
        final d = (lab[ki + c] - lab[ko + c]).toDouble();
        sum += d * d;
      }
      des.add(math.sqrt(sum));
    }
    if (des.length < 5) {
      vals.add(0); // side on the photo border: unknown
      continue;
    }
    des.sort();
    final mid = des.length ~/ 2;
    final de = des.length.isOdd ? des[mid] : (des[mid - 1] + des[mid]) / 2;
    vals.add(math.min(1.0, de / 20.0));
  }
  return vals.reduce((a, b) => a + b) / 4;
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
  final m = _pct8(_sub8(blur), 50);
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
  final det = detectDocument(bgr, aspectHint: aspectHint, fillsFrame: false);
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

/// Round 11c, reference `PAGE_MAX`: a page is never made longer than this
/// (about 170 dpi on A4: sharp in print and for text recognition, ~40 %
/// fewer pixels than an uncapped 8 MP crop for every later step).
const pageMax = 2000;

/// Reference `_cap_page`: the size `w` × `h` scaled down to [pageMax] on
/// the long side.
(int, int) capPage(int w, int h) {
  final m = math.max(w, h);
  if (m <= pageMax) return (w, h);
  final k = pageMax / m;
  return (math.max(1, _roundHalfEven(w * k)), math.max(1, _roundHalfEven(h * k)));
}

/// Perspective-warps [src] to [quad] at the quad's own resolution (at most
/// [pageMax] long, round 11c) — port of
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
  (wt, ht) = capPage(math.max(1, wt), math.max(1, ht));
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

// ---------------------------------------------------------------------------
// Bent page flattening (round 11, P0-14) — port of the reference
// `warp_curved()`. A card or receipt held in the hand bends, so its edges are
// curves. After the 4-corner crop, trace the real page edges, fit a smooth
// curve to each side and stretch them straight (Coons patch), in one remap
// straight from the photo. Document mode only; skips itself when the edges
// are straight or can't be traced reliably.
// ---------------------------------------------------------------------------

const double _curveMargin = 0.20; // search this far outside the crop
const double _curveMinDev = 0.004; // bend under 0.4 % of the page: nothing to do
const double _curveMaxDev = 0.10; // bend over 10 %: tracing unreliable, keep straight
const double _curveMaxCorner = 0.18; // a corner may move this far (clean side only)
const double _curveMinInliers = 0.7;
const double _curveMaxRms = 2.0; // small-copy pixels
const double _curveMaxInward = 0.03; // never cut a coloured edge band off
const double _curveMinValid = 0.5; // at least half of each side traced

/// Reference `_skin_mask`: skin-coloured pixels, any skin tone (YCrCb).
cv.Mat skinMask(cv.Mat bgr) {
  final ycc = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb);
  // Y > 50, Cr 135..180, Cb 77..127.
  final m = cv.inRangebyScalar(ycc, cv.Scalar(51, 135, 77), cv.Scalar(255, 180, 127));
  ycc.dispose();
  final k5 = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  final k15 = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
  final opened = _morph(m, cv.MORPH_OPEN, k5);
  final out = _morph(opened, cv.MORPH_CLOSE, k15);
  for (final x in [m, k5, k15, opened]) {
    x.dispose();
  }
  return out;
}

/// Solves the square system [a]·x = [b] (Gaussian elimination, partial
/// pivoting); null when singular.
List<double>? _solve(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [for (var i = 0; i < n; i++) [...a[i], b[i]]];
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (m[r][c].abs() > m[piv][c].abs()) piv = r;
    }
    if (m[piv][c].abs() < 1e-12) return null;
    final t = m[c];
    m[c] = m[piv];
    m[piv] = t;
    for (var r = 0; r < n; r++) {
      if (r == c) continue;
      final f = m[r][c] / m[c][c];
      for (var k = c; k <= n; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n] / m[i][i]];
}

/// Reference `_fit_side`: one side as e(u) = c0 + c1·u + u(1−u)(c2 + c3·u),
/// e = pixels outwards from the straight crop line. [pinned] keeps both
/// corners (c0 = c1 = 0). Least squares (normal equations), refitted twice
/// without outliers (a finger, text, background leaks).
({List<double> c, double inliers, double rms})? _fitSide(List<double> u, List<double> e, {bool pinned = false}) {
  List<double> row(double x) => pinned
      ? [x * (1 - x), x * x * (1 - x)]
      : [1, x, x * (1 - x), x * x * (1 - x)];
  final rows = [for (final x in u) row(x)];
  final k = rows.first.length;
  var keep = List<bool>.filled(u.length, true);
  List<double>? c;
  double predict(int i) {
    var v = 0.0;
    for (var j = 0; j < k; j++) {
      v += rows[i][j] * c![j];
    }
    return v;
  }

  for (var it = 0; it < 3; it++) {
    if (keep.where((x) => x).length < 8) return null;
    final ata = List.generate(k, (_) => List<double>.filled(k, 0));
    final atb = List<double>.filled(k, 0);
    for (var i = 0; i < u.length; i++) {
      if (!keep[i]) continue;
      for (var a = 0; a < k; a++) {
        atb[a] += rows[i][a] * e[i];
        for (var b = 0; b < k; b++) {
          ata[a][b] += rows[i][a] * rows[i][b];
        }
      }
    }
    c = _solve(ata, atb);
    if (c == null) return null;
    final r = [for (var i = 0; i < u.length; i++) (predict(i) - e[i]).abs()];
    final kept = [for (var i = 0; i < u.length; i++) if (keep[i]) r[i]]..sort();
    final mid = kept.length ~/ 2;
    final mad = (kept.length.isOdd ? kept[mid] : (kept[mid - 1] + kept[mid]) / 2) + 1e-6;
    final lim = math.max(1.5, 3.0 * mad);
    keep = [for (final x in r) x < lim];
  }
  final n = keep.where((x) => x).length;
  if (n < 8) return null;
  var sq = 0.0;
  for (var i = 0; i < u.length; i++) {
    if (!keep[i]) continue;
    final d = predict(i) - e[i];
    sq += d * d;
  }
  return (c: pinned ? [0.0, 0.0, ...c!] : c!, inliers: n / u.length, rms: math.sqrt(sq / n));
}

double _sideE(List<double> c, double u) => c[0] + c[1] * u + u * (1 - u) * (c[2] + c[3] * u);

double _bendOnly(List<double> c, double u) => u * (1 - u) * (c[2] + c[3] * u);

/// Reference `warp_curved` (round 11, P0-14): [warpToQuad] for Document
/// pages, with each side bent to follow the real page edge, and a detected
/// corner moved outwards onto the real corner when its side traces
/// cleanly. [cornersFixed]: the user placed the corners in Adjust edges;
/// they are kept exactly, only the sides may bend. Falls back to
/// [warpToQuad] when nothing bends (by 0.4 % or more).
cv.Mat warpCurved(cv.Mat src, Quad quad, {bool cornersFixed = false}) {
  final q = orderCorners([
    for (final p in quad.points) (x: p.x * src.cols, y: p.y * src.rows),
  ]);
  double d(XY a, XY b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  final wt = math.max(d(q[2], q[3]), d(q[1], q[0])).toInt();
  final ht = math.max(d(q[1], q[2]), d(q[0], q[3])).toInt();
  // Trace on a small copy (long side 800); the final remap is full size.
  final s = math.min(1.0, 800.0 / math.max(wt, ht));
  final w = math.max(16, (wt * s).toInt());
  final h = math.max(16, (ht * s).toInt());
  final mx = (w * _curveMargin).toInt() + 2;
  final my = (h * _curveMargin).toInt() + 2;
  final srcPts = cv.VecPoint2f.fromList([for (final p in q) cv.Point2f(p.x, p.y)]);
  final dstPts = cv.VecPoint2f.fromList([
    cv.Point2f(mx.toDouble(), my.toDouble()),
    cv.Point2f(mx + w - 1.0, my.toDouble()),
    cv.Point2f(mx + w - 1.0, my + h - 1.0),
    cv.Point2f(mx.toDouble(), my + h - 1.0),
  ]);
  final hm = cv.getPerspectiveTransform2f(srcPts, dstPts);
  srcPts.dispose();
  dstPts.dispose();
  final hmv = [for (var r = 0; r < 3; r++) for (var c = 0; c < 3; c++) hm.at<double>(r, c)];
  final sw = w + 2 * mx;
  final sh = h + 2 * my;
  final small = cv.warpPerspective(src, hm, (sw, sh), flags: cv.INTER_AREA, borderMode: cv.BORDER_CONSTANT, borderValue: cv.Scalar.all(0));
  final ones = cv.Mat.fromScalar(src.rows, src.cols, cv.MatType.CV_8UC1, cv.Scalar.all(255));
  final validM = cv.warpPerspective(ones, hm, (sw, sh), flags: cv.INTER_NEAREST);
  ones.dispose();
  hm.dispose();
  cv.Mat plain() => warpToQuad(src, quad);

  // Paper mask: close to the paper colour in the middle of the page, text
  // holes closed, then only the region holding the page centre.
  final labM = cv.cvtColor(small, cv.COLOR_BGR2Lab);
  final skinM = skinMask(small);
  small.dispose();
  final lab = Uint8List.fromList(labM.data);
  labM.dispose();
  final valid = Uint8List.fromList(validM.data);
  validM.dispose();
  final paperRef = _paperColour(lab, sw, my + h ~/ 5, my + 4 * h ~/ 5, mx + w ~/ 5, mx + 4 * w ~/ 5);
  final (lp, ap, bp) = paperRef;
  final paperM = cv.Mat.zeros(sh, sw, cv.MatType.CV_8UC1);
  final pd = paperM.data;
  for (var i = 0; i < sw * sh; i++) {
    final l = lab[i * 3].toDouble();
    final dl = (l - lp) * 0.5;
    final da = lab[i * 3 + 1] - ap;
    final db = lab[i * 3 + 2] - bp;
    if (math.sqrt(dl * dl + da * da + db * db) < 18 && l > lp - 30 && valid[i] > 0) pd[i] = 255;
  }
  final kk = math.max(3, (0.03 * math.min(w, h)).toInt() | 1);
  final ke = cv.getStructuringElement(cv.MORPH_ELLIPSE, (kk, kk));
  final closed = _morph(paperM, cv.MORPH_CLOSE, ke);
  paperM.dispose();
  ke.dispose();
  final labels = cv.Mat.empty();
  final stats = cv.Mat.empty();
  final centroids = cv.Mat.empty();
  final nLbl = cv.connectedComponentsWithStats(closed, labels, stats, centroids, 8, cv.MatType.CV_32S, -1);
  closed.dispose();
  stats.dispose();
  centroids.dispose();
  final lbl = Int32List.fromList(labels.data.buffer.asInt32List(labels.data.offsetInBytes, sw * sh));
  labels.dispose();
  // Round 11b: the page is the paper region covering most of the page's
  // middle half (one centre pixel is often on text, in no region).
  final counts = Int32List(nLbl);
  var midSize = 0;
  for (var y = my + h ~/ 4; y < my + 3 * h ~/ 4; y++) {
    for (var x = mx + w ~/ 4; x < mx + 3 * w ~/ 4; x++) {
      counts[lbl[y * sw + x]]++;
      midSize++;
    }
  }
  counts[0] = 0;
  var cLbl = 0;
  for (var i = 1; i < nLbl; i++) {
    if (counts[i] > counts[cLbl]) cLbl = i;
  }
  if (counts[cLbl] < 0.3 * midSize) {
    skinM.dispose();
    return plain();
  }
  // Fingers hide the edge there.
  final k9 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  final skinD = _dilate(skinM, k9);
  skinM.dispose();
  k9.dispose();
  final skin = Uint8List.fromList(skinD.data);
  skinD.dispose();

  ({List<double> c, double change})? side(String name) {
    final horiz = name == 'top' || name == 'bottom';
    final length = horiz ? w : h;
    final start = horiz ? mx : my;
    final straight = switch (name) {
      'top' => my,
      'bottom' => my + h - 1,
      'left' => mx,
      _ => mx + w - 1,
    };
    final reach = (_curveMaxCorner * (horiz ? h : w)).toInt() + 3;
    final outDir = name == 'top' || name == 'left' ? -1 : 1;
    final us = <double>[];
    final es = <double>[];
    final step = math.max(1, length ~/ 120);
    for (var t = start + length ~/ 20; t < start + length - length ~/ 20; t += step) {
      int? e;
      // Walk from outside towards the page; the first paper pixel is the edge.
      for (var dd = reach; dd >= -reach; dd--) {
        final i = straight + outDir * dd;
        final (y, x) = horiz ? (i, t) : (t, i);
        if (y < 0 || y >= sh || x < 0 || x >= sw || valid[y * sw + x] == 0) continue;
        if (lbl[y * sw + x] == cLbl) {
          e = dd;
          break;
        }
      }
      if (e == null || e == reach) continue; // not seen / runs past the search
      final i = straight + outDir * e;
      final (y, x) = horiz ? (i, t) : (t, i);
      var nearSkin = false;
      for (var yy = math.max(0, y - 4); yy < math.min(sh, y + 5) && !nearSkin; yy++) {
        for (var xx = math.max(0, x - 4); xx < math.min(sw, x + 5); xx++) {
          if (skin[yy * sw + xx] != 0) {
            nearSkin = true;
            break;
          }
        }
      }
      if (nearSkin) continue;
      us.add((t - start) / (length - 1));
      es.add(e.toDouble());
    }
    if (us.length < _curveMinValid * (length * 0.9) / step) return null;
    final other = horiz ? h : w;
    var r = _fitSide(us, es, pinned: cornersFixed);
    if (r == null) return null;
    var c = r.c;
    final lo = math.min(c[0], c[0] + c[1]);
    final hi = math.max(c[0], c[0] + c[1]);
    if (hi > _curveMaxCorner * other || lo < -_curveMaxInward * other || r.inliers < _curveMinInliers || r.rms > _curveMaxRms) {
      // Not clean enough to move corners: keep the detector's.
      r = _fitSide(us, es, pinned: true);
      if (r == null || r.inliers < _curveMinInliers || r.rms > _curveMaxRms) return null;
      c = r.c;
    }
    final tt = _linspace(0, 1, 50);
    final peak = tt.map((u) => _bendOnly(c, u).abs()).reduce(math.max);
    if (peak > _curveMaxDev * other) return null; // unreliable
    if (tt.map((u) => _sideE(c, u)).reduce(math.min) < -_curveMaxInward * other) return null; // would cut in
    return (c: c, change: math.max(peak, math.max(c[0].abs(), (c[0] + c[1]).abs())));
  }

  final bends = <String, List<double>>{};
  final peaks = <double>[];
  for (final name in const ['top', 'bottom', 'left', 'right']) {
    final r = side(name);
    bends[name] = r?.c ?? const [0.0, 0.0, 0.0, 0.0];
    peaks.add(r == null ? 0.0 : r.change / (name == 'top' || name == 'bottom' ? h : w));
  }
  if (peaks.reduce(math.max) < _curveMinDev) return plain();

  // Corners (each may have moved) and the 4 curves through them.
  final x0 = mx.toDouble();
  final x1 = (mx + w - 1).toDouble();
  final y0 = my.toDouble();
  final y1 = (my + h - 1).toDouble();
  double eT(double t) => _sideE(bends['top']!, t);
  double eB(double t) => _sideE(bends['bottom']!, t);
  double eL(double t) => _sideE(bends['left']!, t);
  double eR(double t) => _sideE(bends['right']!, t);
  final tl = (x: x0 - eL(0), y: y0 - eT(0));
  final tr = (x: x1 + eR(0), y: y0 - eT(1));
  final bl = (x: x0 - eL(1), y: y1 + eB(0));
  final br = (x: x1 + eR(1), y: y1 + eB(1));

  // Output size from the curve lengths, at full resolution.
  double arc(double Function(double) fx, double Function(double) fy) {
    final t = _linspace(0, 1, 100);
    var sum = 0.0;
    for (var i = 1; i < t.length; i++) {
      final dx = fx(t[i]) - fx(t[i - 1]);
      final dy = fy(t[i]) - fy(t[i - 1]);
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum;
  }

  final wo0 = math.max(1, _roundHalfEven(math.max(
        arc((t) => tl.x + t * (tr.x - tl.x), (t) => y0 - eT(t)),
        arc((t) => bl.x + t * (br.x - bl.x), (t) => y1 + eB(t)),
      ) / s));
  final ho0 = math.max(1, _roundHalfEven(math.max(
        arc((t) => x0 - eL(t), (t) => tl.y + t * (bl.y - tl.y)),
        arc((t) => x1 + eR(t), (t) => tr.y + t * (br.y - tr.y)),
      ) / s));
  final (wo, ho) = capPage(wo0, ho0);

  // Coons patch on a coarse grid (every 8 px of output), then resized to
  // full maps; small warped space → photo coordinates (one interpolation).
  final gw = math.max(2, wo ~/ 8);
  final gh = math.max(2, ho ~/ 8);
  final us = _linspace(0, 1, gw);
  final vs = _linspace(0, 1, gh);
  final inv = _invert3(hmv);
  final gx = cv.Mat.zeros(gh, gw, cv.MatType.CV_32FC1);
  final gy = cv.Mat.zeros(gh, gw, cv.MatType.CV_32FC1);
  final gxd = gx.data.buffer.asFloat32List(gx.data.offsetInBytes, gw * gh);
  final gyd = gy.data.buffer.asFloat32List(gy.data.offsetInBytes, gw * gh);
  for (var j = 0; j < gh; j++) {
    final v = vs[j];
    final lx = x0 - eL(v);
    final ly = tl.y + v * (bl.y - tl.y);
    final rx = x1 + eR(v);
    final ry = tr.y + v * (br.y - tr.y);
    for (var i = 0; i < gw; i++) {
      final u = us[i];
      final tx = tl.x + u * (tr.x - tl.x);
      final ty = y0 - eT(u);
      final bx = bl.x + u * (br.x - bl.x);
      final by = y1 + eB(u);
      final x = (1 - v) * tx + v * bx + (1 - u) * lx + u * rx -
          ((1 - u) * (1 - v) * tl.x + u * (1 - v) * tr.x + (1 - u) * v * bl.x + u * v * br.x);
      final y = (1 - v) * ty + v * by + (1 - u) * ly + u * ry -
          ((1 - u) * (1 - v) * tl.y + u * (1 - v) * tr.y + (1 - u) * v * bl.y + u * v * br.y);
      final pz = inv[6] * x + inv[7] * y + inv[8];
      gxd[j * gw + i] = (inv[0] * x + inv[1] * y + inv[2]) / pz;
      gyd[j * gw + i] = (inv[3] * x + inv[4] * y + inv[5]) / pz;
    }
  }
  final mapx = cv.resize(gx, (wo, ho), interpolation: cv.INTER_LINEAR);
  final mapy = cv.resize(gy, (wo, ho), interpolation: cv.INTER_LINEAR);
  gx.dispose();
  gy.dispose();
  final out = cv.remap(src, mapx, mapy, cv.INTER_CUBIC, borderMode: cv.BORDER_REPLICATE);
  mapx.dispose();
  mapy.dispose();
  return out;
}

/// The inverse of a row-major 3 × 3 matrix.
List<double> _invert3(List<double> m) {
  final [a, b, c, d, e, f, g, h, i] = m;
  final co0 = e * i - f * h;
  final co1 = -(d * i - f * g);
  final co2 = d * h - e * g;
  final det = a * co0 + b * co1 + c * co2;
  return [
    co0 / det, -(b * i - c * h) / det, (b * f - c * e) / det,
    co1 / det, (a * i - c * g) / det, -(a * f - c * d) / det,
    co2 / det, -(a * h - b * g) / det, (a * e - b * d) / det,
  ];
}

/// The paper colour as the reference measures it: in the given window of an
/// interleaved 8-bit Lab image ([stride] pixels a row), the pixels whose L
/// is at least the window's 60th percentile, per-channel median.
(double, double, double) _paperColour(Uint8List lab, int stride, int y0, int y1, int x0, int x1) {
  final lh = Int32List(256);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      lh[lab[(y * stride + x) * 3]]++;
    }
  }
  var n = 0;
  for (final c in lh) {
    n += c;
  }
  if (n == 0) return (255, 128, 128);
  // numpy percentile (linear) of whole numbers.
  int at(Int32List hst, int k) {
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hst[v];
      if (acc > k) return v;
    }
    return 255;
  }

  final idx = 0.60 * (n - 1);
  final lo = at(lh, idx.floor());
  final p60 = lo + (at(lh, idx.ceil()) - lo) * (idx - idx.floor());
  final hists = List.generate(3, (_) => Int32List(256));
  var m = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final k = (y * stride + x) * 3;
      if (lab[k] < p60) continue;
      hists[0][lab[k]]++;
      hists[1][lab[k + 1]]++;
      hists[2][lab[k + 2]]++;
      m++;
    }
  }
  double median(Int32List hst) => m.isOdd ? at(hst, m ~/ 2).toDouble() : (at(hst, m ~/ 2 - 1) + at(hst, m ~/ 2)) / 2;
  return (median(hists[0]), median(hists[1]), median(hists[2]));
}

// ---------------------------------------------------------------------------
// Finger removal (round 11, P1-11) — port of the reference `find_fingers`,
// `finger_outline` and `remove_fingers`. Fingers holding the page come in
// from its edge. Found on the cropped colour page (before any filter);
// removed only when the user taps Remove, on the filtered page.
// ---------------------------------------------------------------------------

/// Reference `find_fingers`: the mask (8-bit 0/255, page size) of fingers
/// entering the page from an edge, or null. A region counts when it is
/// skin-coloured and clearly redder than the paper (Lab a*) but not deep
/// red cloth, clearly different from the paper colour, and comes in from
/// one edge like a finger (touching at most half that side, reaching 3 %+
/// in).
cv.Mat? findFingers(cv.Mat page) {
  final hFull = page.rows;
  final wFull = page.cols;
  final s = math.min(1.0, 1000.0 / math.max(hFull, wFull));
  final small = s < 1 ? cv.resize(page, ((wFull * s).toInt(), (hFull * s).toInt()), interpolation: cv.INTER_AREA) : page;
  final h = small.rows;
  final w = small.cols;
  final skin = skinMask(small);
  try {
    if (cv.countNonZero(skin) > 0.25 * h * w) return null; // the paper itself is skin-coloured
    final labM = cv.cvtColor(small, cv.COLOR_BGR2Lab);
    final lab = Uint8List.fromList(labM.data);
    labM.dispose();
    final (lp, ap, bp) = _paperColour(lab, w, h ~/ 5, 4 * h ~/ 5, w ~/ 5, 4 * w ~/ 5);
    final labels = cv.Mat.empty();
    final stats = cv.Mat.empty();
    final centroids = cv.Mat.empty();
    final n = cv.connectedComponentsWithStats(skin, labels, stats, centroids, 8, cv.MatType.CV_32S, -1);
    centroids.dispose();
    final lbl = Int32List.fromList(labels.data.buffer.asInt32List(labels.data.offsetInBytes, w * h));
    labels.dispose();
    // Built in Dart, then handed to OpenCV once (never written into native
    // memory from Dart).
    final od = Uint8List(w * h);
    final st = _statsOf(stats, n);
    const m = 4;
    final short = math.min(h, w);
    var any = false;
    for (var i = 1; i < n; i++) {
      final x = st[i * 5];
      final y = st[i * 5 + 1];
      final bw = st[i * 5 + 2];
      final bh = st[i * 5 + 3];
      final a = st[i * 5 + 4];
      if (!(0.002 * h * w < a && a < 0.20 * h * w)) continue;
      // Which edge does it come in from, how wide, how deep?
      final touch = {
        'top': List<bool>.filled(w, false),
        'bottom': List<bool>.filled(w, false),
        'left': List<bool>.filled(h, false),
        'right': List<bool>.filled(h, false),
      };
      var sl = 0.0;
      var sa = 0.0;
      var sb = 0.0;
      var cnt = 0;
      for (var yy = y; yy < y + bh; yy++) {
        for (var xx = x; xx < x + bw; xx++) {
          final k = yy * w + xx;
          if (lbl[k] != i) continue;
          if (yy < m) touch['top']![xx] = true;
          if (yy >= h - m) touch['bottom']![xx] = true;
          if (xx < m) touch['left']![yy] = true;
          if (xx >= w - m) touch['right']![yy] = true;
          sl += lab[k * 3];
          sa += lab[k * 3 + 1];
          sb += lab[k * 3 + 2];
          cnt++;
        }
      }
      int sum(List<bool> v) => v.where((b) => b).length;
      var edge = 'top';
      for (final k in const ['bottom', 'left', 'right']) {
        if (sum(touch[k]!) > sum(touch[edge]!)) edge = k;
      }
      final contact = sum(touch[edge]!);
      final span = contact / touch[edge]!.length;
      if (contact < 0.02 * short) continue; // must really enter from the edge
      if (span > 0.5) continue; // a band along the whole border
      final depth = switch (edge) {
        'top' => y + bh,
        'bottom' => h - y,
        'left' => x + bw,
        _ => w - x,
      };
      if (depth < 0.03 * short) continue;
      final l = sl / cnt;
      final aa = sa / cnt;
      final bb = sb / cnt;
      final dE = math.sqrt((l - lp) * (l - lp) + (aa - ap) * (aa - ap) + (bb - bp) * (bb - bp));
      // 8-bit Lab: a* is stored +128.
      if (dE < 12 || (aa - ap) < 8 || (aa - 128.0) > 35) continue;
      for (var yy = y; yy < y + bh; yy++) {
        for (var xx = x; xx < x + bw; xx++) {
          if (lbl[yy * w + xx] == i) od[yy * w + xx] = 255;
        }
      }
      any = true;
    }
    stats.dispose();
    if (!any) return null;
    final out = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, od);
    // Fill nail / shading holes, then grow over the soft edge and shadow.
    final (cnts, hier) = cv.findContours(out, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    cv.drawContours(out, cnts, -1, cv.Scalar.all(255), thickness: -1);
    cnts.dispose();
    hier.dispose();
    final k = math.max(5, (0.02 * short).toInt() | 1);
    final ke = cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));
    final grown = _dilate(out, ke);
    out.dispose();
    ke.dispose();
    if (s >= 1) return grown;
    final full = cv.resize(grown, (wFull, hFull), interpolation: cv.INTER_LINEAR);
    grown.dispose();
    return full;
  } finally {
    skin.dispose();
    if (!identical(small, page)) small.dispose();
  }
}

/// Reference `finger_outline`: the mask's outlines, normalised to 0..1, for
/// the thin amber line on screen.
List<List<Pt>> fingerOutline(cv.Mat mask) {
  final (_, bin) = cv.threshold(mask, 127, 255, cv.THRESH_BINARY);
  final (cnts, hier) = cv.findContours(bin, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  final out = [
    for (var i = 0; i < cnts.length; i++)
      [for (final p in cnts[i]) Pt(p.x / mask.cols, p.y / mask.rows)],
  ];
  bin.dispose();
  hier.dispose();
  cnts.dispose();
  return out;
}

/// Reference `remove_fingers`: fills [mask] with the paper colour around
/// it, soft-blended. Works on any filter's output. [mask] is resized to
/// [page] when it differs. Returns a new Mat, or [page] itself when the
/// mask is empty.
cv.Mat removeFingers(cv.Mat page, cv.Mat mask) {
  final sized = mask.rows == page.rows && mask.cols == page.cols
      ? mask
      : cv.resize(mask, (page.cols, page.rows), interpolation: cv.INTER_LINEAR);
  final (_, m) = cv.threshold(sized, 127, 255, cv.THRESH_BINARY);
  if (!identical(sized, mask)) sized.dispose();
  if (cv.countNonZero(m) == 0) {
    m.dispose();
    return page;
  }
  final short = math.min(m.rows, m.cols);
  final k = math.max(9, (0.03 * short).toInt() | 1);
  final kr = cv.getStructuringElement(cv.MORPH_RECT, (k, k));
  final grown = _dilate(m, kr);
  kr.dispose();
  final ringM = cv.subtract(grown, m);
  grown.dispose();
  final gray = cv.cvtColor(page, cv.COLOR_BGR2GRAY);
  final ring = ringM.data;
  final g = gray.data;
  final px = page.data;
  final ringVals = Uint8List.fromList([for (var i = 0; i < ring.length; i++) if (ring[i] != 0) g[i]]);
  if (ringVals.isEmpty) {
    for (final x in [m, ringM, gray]) {
      x.dispose();
    }
    return page;
  }
  // Paper pixels of the ring only, not ink: at least its 40th percentile.
  // (A histogram, not a sort: round 11c.)
  final p40 = _pct8(ringVals, 40);
  final hists = List.generate(3, (_) => Int32List(256));
  var n = 0;
  for (var i = 0; i < ring.length; i++) {
    if (ring[i] == 0 || g[i] < p40) continue;
    hists[0][px[i * 3]]++;
    hists[1][px[i * 3 + 1]]++;
    hists[2][px[i * 3 + 2]]++;
    n++;
  }
  int at(Int32List hst, int k) {
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hst[v];
      if (acc > k) return v;
    }
    return 255;
  }

  // numpy's median, then astype(uint8) (truncates).
  int median(Int32List hst) => n.isOdd ? at(hst, n ~/ 2) : (at(hst, n ~/ 2 - 1) + at(hst, n ~/ 2)) ~/ 2;
  final col = n == 0 ? [255, 255, 255] : [median(hists[0]), median(hists[1]), median(hists[2])];
  for (final x in [ringM, gray]) {
    x.dispose();
  }
  // a = blurred mask, fully filled inside.
  final blur = cv.gaussianBlur(m, (0, 0), math.max(2.0, 0.004 * short));
  // Round 11c: blended in OpenCV, not pixel by pixel in Dart:
  // out = px + (colour − px) · alpha, alpha 1 inside, the blur outside;
  // truncated like the reference.
  final am = cv.max(m, blur);
  final af = am.convertTo(cv.MatType.CV_32FC1, alpha: 1 / 255);
  final a3 = cv.merge(cv.VecMat.fromList([af, af, af]));
  final pf = page.convertTo(cv.MatType.CV_32FC3);
  final colM = cv.Mat.fromScalar(page.rows, page.cols, cv.MatType.CV_32FC3, cv.Scalar(col[0].toDouble(), col[1].toDouble(), col[2].toDouble()));
  final diff = cv.subtract(colM, pf);
  final lift = cv.multiply(diff, a3);
  final res = cv.add(pf, lift);
  final out = res.convertTo(cv.MatType.CV_8UC3, beta: _trunc);
  for (final x in [blur, m, am, af, a3, pf, colM, diff, lift, res]) {
    x.dispose();
  }
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
  if (crop != null) {
    // Round 11, P0-14: Document pages follow a bent page's real edges;
    // cards are stiff and keep the plain warp.
    step(
      edits.isDocumentPage
          ? warpCurved(cur, crop, cornersFixed: edits.cornersFixed)
          : warpToQuad(cur, crop, aspect: edits.outputAspect),
    );
  }
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
/// Round 11c: the Laplacian at full detail, the medians from every 2nd row
/// and column of it.
double estimateNoise(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final g32 = gray.convertTo(cv.MatType.CV_32FC1);
  final lap = cv.laplacian(g32, cv.MatType.CV_32F);
  final values = _subF(lap, step: 2);
  for (final m in [gray, g32, lap]) {
    m.dispose();
  }
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

/// Removes sensor noise before any contrast step (reference `_denoise`):
/// round 11c, a bilateral filter on brightness (Y) only (5 px, colour
/// σ = strength × 6, space σ 3), instead of non-local means: the same look
/// on documents, ~20× faster (NLM cost ~8 s per dim-light page on the
/// Tecno KC2). Colour (Cr, Cb) is blotchy and low-frequency, so a blur at
/// 1/4 size is enough. Strength follows the measured noise,
/// `clamp(σ × 0.8, minH, maxH)`, and a clean, well-lit photo (σ < 1.5) is
/// returned as is (a copy: callers dispose it).
cv.Mat denoise(cv.Mat bgr, {double minH = 3.0, double maxH = 6.0}) {
  final sigma = estimateNoise(bgr);
  if (sigma < 1.5) return bgr.clone();
  final strength = (sigma * 0.8).clamp(minH, maxH);
  final w = bgr.cols;
  final h = bgr.rows;
  final ycc = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb);
  final ch = cv.split(ycc);
  ycc.dispose();
  final y = cv.bilateralFilter(ch[0], 5, strength * 6.0, 3.0);
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
/// [ratio] × the best, or [] when the page is evenly sharp, has too little
/// detail to judge, or fewer than [minCells] cells are that soft. Run on
/// the cropped page, before filters.
///
/// Round 7, P0-4: 10–12 retake prompts for 8 pages. A warning now needs 2
/// of 9 cells under 0.4 × the sharpest (was 1 under 0.5).
///
/// Score: on each cell's strongest edges, median |Laplacian| / |gradient|,
/// about 1/σ for an edge blurred by σ whatever the ink's darkness.
List<(int, int)> blurryRegions(cv.Mat warped, {int grid = 3, double ratio = 0.4, int minCells = 2}) {
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
  final soft = [
    for (final e in scores.entries)
      if (e.value < ratio * best) e.key,
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return soft.length < minCells ? const [] : soft;
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
  final sub = _sub8(ch[0]);
  final lo = _pct8(sub, loPct);
  final hi = _pct8(sub, hiPct);
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
/// "marble" patches and contour lines on plain paper. [chroma] scales the
/// colour (Colour boost 1.35, Grayscale 0).
cv.Mat autoFilter(cv.Mat bgr, {double chroma = 1.10}) {
  final dn = denoise(bgr);
  final out = autoFrom(dn, chroma: chroma);
  dn.dispose();
  return out;
}

/// Reference `flatten_page` after its denoise (round 9): gray-world white
/// balance, then shadow removal by dividing by the paper background. Text
/// pages get the full effect; photo-heavy pages keep 25 % of the original
/// light. Float32 BGR (0..255+), not rounded.
cv.Mat flattenPage(cv.Mat dn, {String? cacheKey}) {
  // Round 11c: the gray-world means on every 4th row and column.
  final means = _subMeans3(dn);
  final avg = (means[0] + means[1] + means[2]) / 3;
  final ch8 = cv.split(dn);
  final fc = [
    for (var i = 0; i < 3; i++)
      // Gray-world white balance (strength 0.6), in float.
      ch8[i].convertTo(cv.MatType.CV_32FC1, alpha: 1 + 0.6 * (avg / math.max(means[i], 1.0) - 1)),
  ];
  ch8.dispose();
  final f = cv.merge(cv.VecMat.fromList(fc));
  for (final x in fc) {
    x.dispose();
  }
  final bg = paperBackground(f, cacheKey: cacheKey);
  final floor = cv.Mat.fromScalar(bg.rows, bg.cols, bg.type, cv.Scalar.all(30));
  final bgc = cv.max(bg, floor);
  final flat = cv.divide(f, bgc, scale: 245);
  for (final x in [bg, floor, bgc]) {
    x.dispose();
  }
  // "Text page or photo-heavy page", decided on the shadow-free image.
  final flat8 = flat.convertTo(cv.MatType.CV_8UC3, beta: _trunc);
  final flatGray = cv.cvtColor(flat8, cv.COLOR_BGR2GRAY);
  flat8.dispose();
  final doc = textPageStrength(flatGray);
  flatGray.dispose();
  final blend = 0.75 + 0.25 * doc;
  final out = cv.addWeighted(flat, blend, f, 1 - blend, 0);
  flat.dispose();
  f.dispose();
  return out;
}

/// Reference `_paper_background` (round 9, round 11 P0-9): paper brightness
/// per channel (float32, full size), following shadows closely. At 500 px a
/// small close + median removes the text. Each large dark area is then
/// judged by its outline: a shadow fades out over a soft edge (or is nearly
/// uniform inside) and is divided out; an object (a photo, a black box) has
/// a crisp outline and is protected by filling the background there from
/// the paper around it.
cv.Mat paperBackground(cv.Mat f, {String? cacheKey}) {
  final h = f.rows;
  final w = f.cols;
  final cached = cacheKey == null ? null : _paperBgCache.remove(cacheKey);
  if (cached != null) {
    _paperBgCache[cacheKey!] = cached; // most recent last
    return cv.resize(cached, (w, h), interpolation: cv.INTER_CUBIC);
  }
  final small = _paperBackgroundSmall(f);
  final out = cv.resize(small, (w, h), interpolation: cv.INTER_CUBIC);
  if (cacheKey == null) {
    small.dispose();
  } else {
    _paperBgCache[cacheKey] = small;
    while (_paperBgCache.length > 6) {
      _paperBgCache.remove(_paperBgCache.keys.first)!.dispose();
    }
  }
  return out;
}

/// The paper background at 500 px of the pages Enhance and exports render
/// again and again (one per cleaned page and size): Auto, Colour boost,
/// Grayscale and B&W print all start from the same one, and its object
/// fill (inpaint) takes ~0.3 s on a packaging photo. Lives in the worker.
final Map<String, cv.Mat> _paperBgCache = {};

cv.Mat _paperBackgroundSmall(cv.Mat f) {
  final h = f.rows;
  final w = f.cols;
  final s = 500.0 / math.max(h, w);
  final sw = math.max(1, (w * s).toInt());
  final sh = math.max(1, (h * s).toInt());
  final f8 = f.convertTo(cv.MatType.CV_8UC3, beta: _trunc);
  final small = cv.resize(f8, (sw, sh), interpolation: cv.INTER_AREA);
  f8.dispose();
  const kk = 7;
  final k = cv.getStructuringElement(cv.MORPH_RECT, (kk, kk));
  // CLOSE, not just dilate: removes dark text but keeps a shadow's edge
  // where it is (a plain dilate left a dark streak along hard shadows).
  final closed = _morph(small, cv.MORPH_CLOSE, k);
  small.dispose();
  var bg = cv.medianBlur(closed, kk + 2);
  closed.dispose();
  final y8 = cv.cvtColor(bg, cv.COLOR_BGR2GRAY);
  final p = percentile8(y8, 90);
  final yF = y8.convertTo(cv.MatType.CV_32FC1);
  final sx = cv.sobel(yF, cv.MatType.CV_32F, 1, 0);
  final sy = cv.sobel(yF, cv.MatType.CV_32F, 0, 1);
  final gmM = cv.magnitude(sx, sy);
  final gm = _floats(gmM);
  for (final x in [yF, sx, sy, gmM]) {
    x.dispose();
  }
  final yv = Uint8List.fromList(y8.data);
  // dark = Y < 0.85 P (Y is whole numbers).
  final (_, dark) = cv.threshold(y8, (0.85 * p).ceil() - 1.0, 1, cv.THRESH_BINARY_INV);
  y8.dispose();
  final labels = cv.Mat.empty();
  final stats = cv.Mat.empty();
  final centroids = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(dark, labels, stats, centroids, 8, cv.MatType.CV_32S, -1);
  centroids.dispose();
  dark.dispose();
  final hole = cv.Mat.zeros(sh, sw, cv.MatType.CV_8UC1);
  final minArea = 0.004 * sw * sh;
  final k5 = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  final st = _statsOf(stats, n);
  for (var i = 1; i < n; i++) {
    if (st[i * 5 + 4] < minArea) continue;
    // Work in the area's bounding box plus a margin wider than the kernels,
    // so the morphology gives the same pixels as on the whole image.
    final x0 = math.max(0, st[i * 5] - 4);
    final y0 = math.max(0, st[i * 5 + 1] - 4);
    final x1 = math.min(sw, st[i * 5] + st[i * 5 + 2] + 4);
    final y1 = math.min(sh, st[i * 5 + 1] + st[i * 5 + 3] + 4);
    final rw = x1 - x0;
    final rh = y1 - y0;
    final rect = cv.Rect(x0, y0, rw, rh);
    final roi = labels.region(rect);
    final lc = roi.clone();
    roi.dispose();
    final id = cv.Mat.fromScalar(rh, rw, cv.MatType.CV_32SC1, cv.Scalar.all(i.toDouble()));
    final m = cv.compare(lc, id, cv.CMP_EQ);
    lc.dispose();
    id.dispose();
    final inner = cv.erode(m, k, borderValue: _neutralBorder);
    final dil5 = _dilate(m, k5);
    final ero5 = cv.erode(m, k5, borderValue: _neutralBorder);
    final band = cv.subtract(dil5, ero5);
    final md = m.data;
    final innerD = inner.data;
    final bandD = band.data;
    int full(int j) => (y0 + j ~/ rw) * sw + x0 + j % rw;
    var innerCount = 0;
    for (final v in innerD) {
      if (v != 0) innerCount++;
    }
    final useInner = innerCount >= 20 ? innerD : md;
    // Spread of the brightness inside (relative to its mean).
    var sum = 0.0;
    var cnt = 0;
    for (var j = 0; j < useInner.length; j++) {
      if (useInner[j] != 0) {
        sum += yv[full(j)];
        cnt++;
      }
    }
    final mean = sum / cnt;
    var sq = 0.0;
    for (var j = 0; j < useInner.length; j++) {
      if (useInner[j] != 0) {
        final d = yv[full(j)] - mean;
        sq += d * d;
      }
    }
    final cvar = math.sqrt(sq / cnt) / math.max(1.0, mean);
    // How crisp its outline is, relative to its contrast to the paper.
    final inside = <int>[];
    final edge = <double>[];
    for (var j = 0; j < md.length; j++) {
      if (md[j] != 0) inside.add(yv[full(j)]);
      if (bandD[j] != 0) edge.add(gm[full(j)] / 8.0);
    }
    inside.sort();
    final mid = inside.length ~/ 2;
    final median = inside.length.isOdd ? inside[mid].toDouble() : (inside[mid - 1] + inside[mid]) / 2;
    final contrast = math.max(1.0, p - median);
    final edgeSharp = edge.isEmpty ? 0.0 : _exactPercentile(Float32List.fromList(edge), 90) / contrast;
    final isShadow = cvar < 0.10 || edgeSharp < 0.20;
    if (!isShadow) {
      final hr = hole.region(rect);
      hr.setTo(cv.Scalar.all(255), mask: m);
      hr.dispose();
    }
    for (final x in [m, inner, dil5, ero5, band]) {
      x.dispose();
    }
  }
  for (final x in [labels, stats, k5]) {
    x.dispose();
  }
  final opened = _morph(hole, cv.MORPH_OPEN, k); // drop thin shadow-edge bands
  hole.dispose();
  final holes = _dilate(opened, k);
  opened.dispose();
  k.dispose();
  final count = cv.countNonZero(holes);
  if (count > 0 && count < 0.6 * sw * sh) {
    final filled = cv.inpaint(bg, holes, 15, cv.INPAINT_TELEA);
    bg.dispose();
    bg = filled;
  }
  holes.dispose();
  final bgF = bg.convertTo(cv.MatType.CV_32FC3);
  bg.dispose();
  final blurred = cv.gaussianBlur(bgF, (0, 0), 2.5); // float + blur: no steps
  bgF.dispose();
  return blurred;
}

/// Reference `_text_page_strength`: 1.0 for a text page (paper + dark ink,
/// few mid-tones), 0.0 for a photo-heavy page; fades between.
double textPageStrength(cv.Mat gray) {
  final g = cv.resize(gray, (math.max(1, gray.cols ~/ 4), math.max(1, gray.rows ~/ 4)), interpolation: cv.INTER_AREA);
  final p = percentile8(g, 85);
  var mid = 0;
  final d = g.data;
  for (final v in d) {
    if (v > 0.35 * p && v < 0.80 * p) mid++;
  }
  final frac = mid / d.length;
  g.dispose();
  return ((0.22 - frac) / 0.10).clamp(0.0, 1.0);
}

/// [autoFilter] after its denoise, from an already cleaned page (round 6,
/// P0-2: each page is cleaned once and every filter starts from that).
/// [cacheKey] names [dn] (a cleaned page file and size) so its paper
/// background is worked out once for every filter.
cv.Mat autoFrom(cv.Mat dn, {double chroma = 1.10, String? cacheKey}) {
  final merged = flattenPage(dn, cacheKey: cacheKey);
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
  final lSub = _subF(labCh[0]);
  final lo = _percentileOf(lSub, 1);
  final hi = _percentileOf(lSub, 99.5);
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
  // Round 11b: dim-light grain, on text pages only.
  final mag = cv.magnitude(labCh[1], labCh[2]);
  final wl = despeckleL(w.l, w.strength, mag);
  mag.dispose();
  if (!identical(wl, w.l)) w.l.dispose();
  // Neutral paper, [chroma] × colour elsewhere.
  final cA = w.chroma == null
      ? labCh[1].convertTo(cv.MatType.CV_32FC1, alpha: chroma)
      : cv.multiply(labCh[1], w.chroma!, scale: chroma);
  final cB = w.chroma == null
      ? labCh[2].convertTo(cv.MatType.CV_32FC1, alpha: chroma)
      : cv.multiply(labCh[2], w.chroma!, scale: chroma);
  w.chroma?.dispose();
  final lab2 = cv.merge(cv.VecMat.fromList([wl, cA, cB]));
  for (final x in [wl, cA, cB]) {
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

/// Reference `_despeckle_L` (round 11b): dim-light photos leave small grey
/// sensor-noise dots on the paper after whitening. On text pages
/// ([strength] > 0) and neutral grey pixels ([chroma] < 12) only:
/// 1. faint grain — light grey (L 75..100) not near ink (L < 60 within
///    0.25 % of the page) goes towards white;
/// 2. specks — tiny isolated non-white dots (≤ 0.0025 % of the page) whose
///    darkest pixel is still light (L > 40) go towards white.
/// Text, i-dots, commas and pen strokes are darker or bigger. Float L
/// (0..100) in; a new Mat out, or [l] itself when [strength] is 0.
cv.Mat despeckleL(cv.Mat l, double strength, cv.Mat chroma) {
  if (strength <= 0) return l;
  final h = l.rows;
  final w = l.cols;
  final n = h * w;
  final lv = _floats(l);
  final cr = _floats(chroma);
  // 1) Faint grain.
  final ink = _below(l, 60);
  final r = math.max(2, (0.0025 * math.max(h, w)).toInt());
  final k = cv.getStructuringElement(cv.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1));
  final near = _dilate(ink, k);
  ink.dispose();
  k.dispose();
  final nd = Uint8List.fromList(near.data);
  near.dispose();
  for (var i = 0; i < n; i++) {
    final v = lv[i];
    if (v > 75 && v < 100 && nd[i] == 0 && cr[i] < 12) lv[i] = v + strength * (100 - v);
  }
  // 2) Darker specks.
  final l1 = _matOf(lv, h, w);
  final notWhite = _below(l1, 92);
  l1.dispose();
  final labels = cv.Mat.empty();
  final stats = cv.Mat.empty();
  final centroids = cv.Mat.empty();
  final count = cv.connectedComponentsWithStats(notWhite, labels, stats, centroids, 8, cv.MatType.CV_32S, -1);
  notWhite.dispose();
  centroids.dispose();
  if (count > 1) {
    final lab = Int32List.fromList(labels.data.buffer.asInt32List(labels.data.offsetInBytes, n));
    final amax = math.max(4, (2.5e-5 * h * w).toInt());
    final mins = Float32List(count)..fillRange(0, count, 100);
    for (var i = 0; i < n; i++) {
      final c = lab[i];
      if (lv[i] < mins[c]) mins[c] = lv[i];
    }
    final st = _statsOf(stats, count);
    final speck = List<bool>.generate(count, (c) => c > 0 && st[c * 5 + 4] <= amax && mins[c] > 40);
    if (speck.contains(true)) {
      for (var i = 0; i < n; i++) {
        if (speck[lab[i]] && cr[i] < 12) lv[i] = lv[i] + strength * (100 - lv[i]);
      }
    }
  }
  labels.dispose();
  stats.dispose();
  return _matOf(lv, h, w);
}

/// 8-bit mask (1 where the float [m] is below [t]).
cv.Mat _below(cv.Mat m, double t) {
  // THRESH_BINARY_INV marks v <= t; just under t gives v < t.
  final (_, f) = cv.threshold(m, t - 1e-4, 1, cv.THRESH_BINARY_INV);
  final out = f.convertTo(cv.MatType.CV_8UC1);
  f.dispose();
  return out;
}

/// A float one-channel Mat holding [v].
cv.Mat _matOf(Float32List v, int h, int w) => cv.Mat.fromList(h, w, cv.MatType.CV_32FC1, v);

/// Reference `_whiten_paper` (P0-2), on float Lab channels: if the page is
/// mostly plain paper with dark text (few mid-tones), push the paper to pure
/// white with a smoothstep from 70 % of the paper level, so there's no
/// visible edge or step; text below that keeps its weight. Photos and
/// packaging have many mid-tones, and the effect fades out (never a hard
/// switch). Returns the new L, the chroma multiplier (null = unchanged) and
/// the strength (0..1, round 11b: [despeckleL] uses it).
/// Statistics come from a ≤ 1000 px sample; the curve runs at full size.
({cv.Mat l, cv.Mat? chroma, double strength}) whitenPaper(cv.Mat l, cv.Mat a, cv.Mat b) {
  final chroma = cv.magnitude(a, b);
  // Round 11c: statistics on every 4th row and column.
  final ls = _subF(l);
  final cs = _subF(chroma);
  final p40 = _percentileOf(Float32List.fromList(ls), 40);
  final paper = Float32List.fromList([
    for (var i = 0; i < ls.length; i++)
      if (cs[i] < 12 && ls[i] > p40) ls[i],
  ]);
  if (paper.isEmpty) {
    chroma.dispose();
    return (l: l, chroma: null, strength: 0.0);
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
    return (l: l, chroma: null, strength: 0.0);
  }
  final t0 = 0.70 * pL;
  final span = math.max(1e-3, pL - t0);
  // Round 11c: the curve as lookup tables of 1001 steps (L 0.0..100.0 in
  // 0.1 steps): x = clip((L − t0) / span, 0, 1), s = x²(3 − 2x) · strength,
  // L2 = L + s · (100 − L), k = 1 − 0.8 · s (paper tint to neutral, only
  // where chroma < 20).
  final lTab = Float32List(1001);
  final kTab = Float32List(1001);
  for (var i = 0; i <= 1000; i++) {
    final g = i / 10.0;
    final x = ((g - t0) / span).clamp(0.0, 1.0);
    final st = x * x * (3 - 2 * x) * strength;
    lTab[i] = g + st * (100.0 - g);
    kTab[i] = 1.0 - 0.8 * st;
  }
  final (h, w) = (l.rows, l.cols);
  final lc = l.isContinuous ? l : l.clone();
  final cc = chroma.isContinuous ? chroma : chroma.clone();
  final lb = lc.data;
  final cb = cc.data;
  final lv = lb.buffer.asFloat32List(lb.offsetInBytes, h * w);
  final cvals = cb.buffer.asFloat32List(cb.offsetInBytes, h * w);
  final l2 = Float32List(h * w);
  final k = Float32List(h * w);
  for (var i = 0; i < h * w; i++) {
    final idx = (lv[i] * 10.0 + 0.5).clamp(0.0, 1000.0).toInt();
    l2[i] = lTab[idx];
    k[i] = cvals[i] < 20 ? kTab[idx] : 1.0;
  }
  if (!identical(lc, l)) lc.dispose();
  if (!identical(cc, chroma)) cc.dispose();
  chroma.dispose();
  return (l: _matOf(l2, h, w), chroma: _matOf(k, h, w), strength: strength);
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

/// Round 11c, the reference's `_pct`: statistics on every [step]-th row
/// and column (1/16 of the pixels at 4), read out once. One channel, 8-bit.
Uint8List _sub8(cv.Mat m, {int step = 4}) {
  final cont = m.isContinuous ? m : m.clone();
  final d = cont.data;
  final (h, w) = (cont.rows, cont.cols);
  final out = Uint8List(((h + step - 1) ~/ step) * ((w + step - 1) ~/ step));
  var i = 0;
  for (var y = 0; y < h; y += step) {
    final row = y * w;
    for (var x = 0; x < w; x += step) {
      out[i++] = d[row + x];
    }
  }
  if (!identical(cont, m)) cont.dispose();
  return out;
}

/// [_sub8] for one float channel.
Float32List _subF(cv.Mat m, {int step = 4}) {
  final cont = m.isContinuous ? m : m.clone();
  final bytes = cont.data;
  final d = bytes.buffer.asFloat32List(bytes.offsetInBytes, cont.rows * cont.cols);
  final out = _subList(d, cont.cols, cont.rows, step: step);
  if (!identical(cont, m)) cont.dispose();
  return out;
}

/// [_sub8] for float values already read out ([w] × [h], row by row).
Float32List _subList(Float32List d, int w, int h, {int step = 4}) {
  final out = Float32List(((h + step - 1) ~/ step) * ((w + step - 1) ~/ step));
  var i = 0;
  for (var y = 0; y < h; y += step) {
    final row = y * w;
    for (var x = 0; x < w; x += step) {
      out[i++] = d[row + x];
    }
  }
  return out;
}

/// Per-channel means of a 3-channel 8-bit image on every 4th row and
/// column (the reference's `f[::4, ::4].mean`).
List<double> _subMeans3(cv.Mat m, {int step = 4}) {
  final cont = m.isContinuous ? m : m.clone();
  final d = cont.data;
  final (h, w) = (cont.rows, cont.cols);
  final sum = [0.0, 0.0, 0.0];
  var n = 0;
  for (var y = 0; y < h; y += step) {
    final row = y * w * 3;
    for (var x = 0; x < w; x += step) {
      final k = row + x * 3;
      sum[0] += d[k];
      sum[1] += d[k + 1];
      sum[2] += d[k + 2];
      n++;
    }
  }
  if (!identical(cont, m)) cont.dispose();
  return [for (final v in sum) n == 0 ? 0.0 : v / n];
}

/// The rows of a connected-components stats Mat (left, top, width,
/// height, area per label), read once.
Int32List _statsOf(cv.Mat stats, int n) =>
    Int32List.fromList(stats.data.buffer.asInt32List(stats.data.offsetInBytes, n * 5));

/// numpy.percentile (linear) of 8-bit values, from a 256-bin histogram.
double _pct8(Uint8List v, double pct) {
  if (v.isEmpty) return 0;
  final hist = Int32List(256);
  for (final x in v) {
    hist[x]++;
  }
  final idx = pct / 100 * (v.length - 1);
  final lo = idx.floor();
  final hi = idx.ceil();
  int valueAt(int k) {
    var acc = 0;
    for (var x = 0; x < 256; x++) {
      acc += hist[x];
      if (acc > k) return x;
    }
    return 255;
  }

  final a = valueAt(lo);
  final b = valueAt(hi);
  return a + (b - a) * (idx - lo);
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

/// "B&W print": pure black text on white, for photocopies. Round 9: the
/// finished Grayscale page thresholded (paper already white, shadow rims
/// gone): ink is clearly darker than its neighbourhood (adaptive, C = 18)
/// AND darker than 200.
cv.Mat bwPrintFilter(cv.Mat bgr) {
  final dn = denoise(bgr);
  final out = bwPrintFrom(dn);
  dn.dispose();
  return out;
}

/// [bwPrintFilter] from an already cleaned page.
cv.Mat bwPrintFrom(cv.Mat dn, {String? cacheKey}) {
  final g3 = grayscaleFrom(dn, cacheKey: cacheKey);
  final gray = cv.cvtColor(g3, cv.COLOR_BGR2GRAY);
  g3.dispose();
  final block = math.max(15, (math.min(gray.rows, gray.cols) ~/ 40) | 1);
  final loc = cv.adaptiveThreshold(gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 18);
  final (_, light) = cv.threshold(gray, 199, 255, cv.THRESH_BINARY);
  final bw = cv.bitwiseOR(loc, light);
  final med = cv.medianBlur(bw, 3);
  final out = cv.cvtColor(med, cv.COLOR_GRAY2BGR);
  for (final x in [gray, loc, light, bw, med]) {
    x.dispose();
  }
  return out;
}

/// "Grayscale": Auto without colour (same white paper, no shadows).
cv.Mat grayscaleFilter(cv.Mat bgr) => autoFilter(bgr, chroma: 0).._toGray();

/// [grayscaleFilter] from an already cleaned page.
cv.Mat grayscaleFrom(cv.Mat dn, {String? cacheKey}) => autoFrom(dn, chroma: 0, cacheKey: cacheKey).._toGray();

extension on cv.Mat {
  /// In place: BGR → gray → BGR.
  void _toGray() {
    final g = cv.cvtColor(this, cv.COLOR_BGR2GRAY);
    cv.cvtColor(g, cv.COLOR_GRAY2BGR, dst: this);
    g.dispose();
  }
}

/// "Colour boost": Auto with stronger colours (stamps, highlighter).
cv.Mat colorBoostFilter(cv.Mat bgr) => autoFilter(bgr, chroma: 1.35);

/// [colorBoostFilter] from an already cleaned page.
cv.Mat colorBoostFrom(cv.Mat dn, {String? cacheKey}) => autoFrom(dn, chroma: 1.35, cacheKey: cacheKey);

/// Filters whose Enhance result is cached between renders (the Auto look).
bool usesAutoBase(FilterType f) => f == FilterType.auto;

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
cv.Mat applyFilterFromClean(cv.Mat clean, FilterType filter, {String? cacheKey}) => switch (filter) {
  FilterType.original => clean.clone(),
  FilterType.auto => autoFrom(clean, cacheKey: cacheKey),
  FilterType.idColor => idColorFrom(clean),
  FilterType.colorBoost => colorBoostFrom(clean, cacheKey: cacheKey),
  FilterType.grayscale => grayscaleFrom(clean, cacheKey: cacheKey),
  FilterType.bwPrint => bwPrintFrom(clean, cacheKey: cacheKey),
};

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

/// Reference `clean_page_border` (round 8, P0-7): table left in the crop of
/// a curled or wavy page prints as dark lines along its sides. Dark areas
/// (< 80 % of the paper) that touch the image edge and stay within [band]
/// of it are painted with the paper colour; dark areas reaching deeper (a
/// black header bar, a photo printed to the edge) are page content and
/// stay. Returns a new Mat.
cv.Mat cleanPageBorder(cv.Mat bgr, {double band = 0.05}) {
  final h = bgr.rows;
  final w = bgr.cols;
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  try {
    final p = _pct8(_sub8(gray), 90); // paper brightness
    final b = math.max(2, _roundHalfEven(band * math.min(h, w)));
    // Round 11c: only the 4 edge strips, 2 bands wide. A dark area's depth
    // is its deepest pixel's distance from the nearest image edge, measured
    // in its strip (our change to the reference, which reads it from the
    // area's box: a thin frame of table all around the page then reads as a
    // full strip deep and stays).
    final b2 = math.min(2 * b, math.min(h ~/ 2, w ~/ 2));
    final mask = Uint8List(h * w);
    var any = false;
    final strips = [
      cv.Rect(0, 0, w, b2),
      cv.Rect(0, h - b2, w, b2),
      cv.Rect(0, 0, b2, h),
      cv.Rect(w - b2, 0, b2, h),
    ];
    for (final r in strips) {
      if (r.width <= 0 || r.height <= 0) continue;
      final g = gray.region(r);
      final dark = _below(g, 0.80 * p);
      g.dispose();
      final labels = cv.Mat.empty();
      final stats = cv.Mat.empty();
      final centroids = cv.Mat.empty();
      final n = cv.connectedComponentsWithStats(dark, labels, stats, centroids, 8, cv.MatType.CV_32S, -1);
      dark.dispose();
      stats.dispose();
      centroids.dispose();
      try {
        if (n <= 1) continue;
        final (sh, sw) = (r.height, r.width);
        final lab = labels.data.buffer.asInt32List(labels.data.offsetInBytes, sh * sw);
        final maxd = Int32List(n);
        final touch = List<bool>.filled(n, false);
        for (var y = 0; y < sh; y++) {
          final gy = r.y + y;
          final dy = math.min(gy, h - 1 - gy);
          final lrow = y * sw;
          for (var x = 0; x < sw; x++) {
            final l = lab[lrow + x];
            if (l == 0) continue;
            final gx = r.x + x;
            final d = math.min(math.min(gx, w - 1 - gx), dy);
            if (d > maxd[l]) maxd[l] = d;
            if (d == 0) touch[l] = true;
          }
        }
        final keep = [for (var i = 0; i < n; i++) i != 0 && touch[i] && maxd[i] < b];
        if (!keep.contains(true)) continue;
        any = true;
        for (var y = 0; y < sh; y++) {
          final row = (r.y + y) * w + r.x;
          final lrow = y * sw;
          for (var x = 0; x < sw; x++) {
            if (keep[lab[lrow + x]]) mask[row + x] = 255;
          }
        }
      } finally {
        labels.dispose();
      }
    }
    if (!any) return bgr.clone();
    // Include the soft rim.
    final m = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, mask);
    final k = cv.getStructuringElement(cv.MORPH_ELLIPSE, (5, 5));
    final grown = _dilate(m, k);
    m.dispose();
    k.dispose();
    // Paper colour: the per-channel median of the bright pixels, on every
    // 4th row and column.
    final hist = List.generate(3, (_) => Int32List(256));
    final src = bgr.isContinuous ? bgr : bgr.clone();
    final px = src.data;
    final gd = gray.data;
    final paperLim = 0.92 * p;
    var count = 0;
    for (var y = 0; y < h; y += 4) {
      for (var x = 0; x < w; x += 4) {
        final i = y * w + x;
        if (gd[i] >= paperLim) {
          hist[0][px[i * 3]]++;
          hist[1][px[i * 3 + 1]]++;
          hist[2][px[i * 3 + 2]]++;
          count++;
        }
      }
    }
    if (!identical(src, bgr)) src.dispose();
    int median(Int32List hst) {
      int at(int k) {
        var acc = 0;
        for (var v = 0; v < 256; v++) {
          acc += hst[v];
          if (acc > k) return v;
        }
        return 255;
      }

      // numpy's median, then astype(uint8) (truncates).
      return count.isOdd ? at(count ~/ 2) : (at(count ~/ 2 - 1) + at(count ~/ 2)) ~/ 2;
    }

    final colour = count == 0
        ? cv.Scalar.all(255)
        : cv.Scalar(median(hist[0]).toDouble(), median(hist[1]).toDouble(), median(hist[2]).toDouble());
    final out = bgr.clone();
    out.setTo(colour, mask: grown);
    grown.dispose();
    return out;
  } finally {
    gray.dispose();
  }
}

/// [cleanPageBorder] where it belongs: Document pages after a filter. Not
/// ID / passport cards, passport photos, or the raw Original. Takes
/// ownership of [filtered].
cv.Mat withCleanBorder(cv.Mat filtered, PageEdits edits) {
  if (edits.outputAspect != null || edits.photoWidthMm != null || edits.filter == FilterType.original) {
    return filtered;
  }
  final out = cleanPageBorder(filtered);
  filtered.dispose();
  return out;
}

/// What comes after the filter: the page border clean-up (round 8), the
/// sliders, a passport photo's finish and signatures. Takes ownership of
/// [filtered].
cv.Mat finishEdits(cv.Mat filtered, PageEdits edits, {StepTimer? timer}) {
  final bordered = _withoutFingers(withCleanBorder(filtered, edits), edits);
  final adjusted = brightnessContrast(bordered, edits);
  bordered.dispose();
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
  final filtered = applyFilterFromClean(sized, edits.filter, cacheKey: '$basePath@${sized.cols}');
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

/// Background colours (BGR) from [PhotoBackgrounds.argb] (round 10, P1-7:
/// white, off-white, light and sky blue, and the deep studio blue).
cv.Scalar? photoBackgroundColor(PhotoBackground b) {
  final c = PhotoBackgrounds.argb(b);
  if (c == null) return null;
  return cv.Scalar((c & 0xFF).toDouble(), ((c >> 8) & 0xFF).toDouble(), ((c >> 16) & 0xFF).toDouble());
}

/// Passport photo finish: [enhancePhoto] (if on), then the background
/// colour. The person mask (whole upright photo) is warped with the same
/// crop as the photo. Returns [page] itself when there's nothing to do.
cv.Mat _withPhotoFinish(cv.Mat page, PageEdits edits) {
  final color = photoBackgroundColor(edits.photoBackground);
  final enhance = edits.photoEnhance;
  if (color == null && enhance == PhotoEnhance.off) return page;
  cv.Mat? warped;
  // The whole-photo mask, kept for placing the face box.
  cv.Mat? mask0;
  final path = edits.backgroundMaskPath;
  if (path != null) {
    final mask = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
    if (mask.isEmpty) {
      mask.dispose();
    } else {
      // The crop is in fractions of the upright photo, so it fits the mask too.
      warped = cropAndRotate(mask, edits);
      if (identical(mask, warped)) {
        mask0 = mask.clone();
      } else {
        mask0 = mask;
      }
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
    final face = edits.faceBox == null || mask0 == null
        ? null
        : _faceInCrop(edits.faceBox!, mask0, edits, (capped.cols, capped.rows));
    final out = finishPhoto(capped, warped, color: color, enhance: enhance, face: face);
    if (!identical(capped, page) && !identical(out, capped)) capped.dispose();
    return out;
  } finally {
    warped?.dispose();
    mask0?.dispose();
  }
}

/// Round 11, P1-11: the fingers the user removed, filled with paper on the
/// filtered page. Takes ownership of [page].
cv.Mat _withoutFingers(cv.Mat page, PageEdits edits) {
  final path = edits.fingerMaskPath;
  if (!edits.fingersRemoved || path == null || !edits.isDocumentPage) return page;
  final mask = cv.imread(path, flags: cv.IMREAD_GRAYSCALE);
  if (mask.isEmpty) {
    mask.dispose();
    return page;
  }
  final out = removeFingers(page, mask);
  mask.dispose();
  disposeUnless(page, out);
  return out;
}

/// Round 11b, P1-14: the reference's `FACE_TARGET_L`, the Lab L the middle
/// of the face is lifted to.
const double faceTargetL = 64;

/// The reference's `passport_brighten` (round 11b, P1-14): a natural lift
/// of the person only, for passport photos. Stretches the person's
/// lightness (black point kept, highlights lifted a little, never
/// clipped), then a gamma that brings the middle of the face to L 64;
/// gives the skin its colour back (+22 %) and sharpens eyes and hair a
/// little. The background is untouched; no smoothing.
/// [person]: 8-bit (255 = person) or float 0..1, the size of [bgr];
/// [face]: (x0, y0, x1, y1) in [bgr]'s pixels. Always a new image.
cv.Mat passportBrighten(cv.Mat bgr, cv.Mat person, (int, int, int, int) face) {
  final tmp = <cv.Mat>[];
  cv.Mat t(cv.Mat m) {
    tmp.add(m);
    return m;
  }

  try {
    final (h, w) = (bgr.rows, bgr.cols);
    final p = t(person.type == cv.MatType.CV_32FC1 ? person.clone() : person.convertTo(cv.MatType.CV_32FC1, alpha: 1 / 255));
    final lab = t(cv.cvtColor(t(bgr.convertTo(cv.MatType.CV_32FC3, alpha: 1 / 255)), cv.COLOR_BGR2Lab));
    final ch = cv.split(lab);
    final (lL, la, lb) = (t(ch[0].clone()), t(ch[1].clone()), t(ch[2].clone()));
    ch.dispose();
    // L over the body (person > 0.5).
    final n = h * w;
    final lv = Float32List.fromList(lL.data.buffer.asFloat32List(lL.data.offsetInBytes, n));
    final pv = Float32List.fromList(p.data.buffer.asFloat32List(p.data.offsetInBytes, n));
    var count = 0;
    for (var i = 0; i < n; i++) {
      if (pv[i] > 0.5) lv[count++] = lv[i];
    }
    if (count < 100) return bgr.clone();
    final body = Float32List.sublistView(lv, 0, count);
    final lo = _percentileOf(body, 1);
    final hi = _percentileOf(body, 99.5);
    final hi2 = hi + 0.35 * (100 - hi);
    final k = (hi2 - 3) / math.max(1e-3, hi - lo);
    var ln = t(lL.convertTo(cv.MatType.CV_32FC1, alpha: k, beta: 3 - lo * k));
    ln = t(cv.threshold(ln, 100, 0, cv.THRESH_TRUNC).$2);
    ln = t(cv.threshold(ln, 0, 0, cv.THRESH_TOZERO).$2);
    final (x0, y0, x1, y1) = face;
    final fx0 = x0.clamp(0, w - 1);
    final fy0 = y0.clamp(0, h - 1);
    final fx1 = x1.clamp(fx0 + 1, w);
    final fy1 = y1.clamp(fy0 + 1, h);
    final faceL = t(ln.region(cv.Rect(fx0, fy0, fx1 - fx0, fy1 - fy0)).clone());
    final fm = _median(Float32List.fromList(faceL.data.buffer.asFloat32List(faceL.data.offsetInBytes, faceL.rows * faceL.cols)));
    if (fm < 1) return bgr.clone();
    final g = (math.log(faceTargetL / 100) / math.log(fm / 100)).clamp(0.75, 1.0);
    // Midtones up, black and white points kept.
    ln = t(cv.pow(t(ln.convertTo(cv.MatType.CV_32FC1, alpha: 0.01)), g).convertTo(cv.MatType.CV_32FC1, alpha: 100));
    // Lo = person · Ln + (1 − person) · L.
    final lOut = t(cv.add(lL, t(cv.multiply(p, t(cv.subtract(ln, lL))))));
    // Brightening greys skin: colour back +22 %.
    final kc = t(p.convertTo(cv.MatType.CV_32FC1, alpha: 0.22, beta: 1));
    final merged = t(cv.merge(cv.VecMat.fromList([lOut, t(cv.multiply(la, kc)), t(cv.multiply(lb, kc))])));
    final out = t(t(cv.cvtColor(merged, cv.COLOR_Lab2BGR)).convertTo(cv.MatType.CV_32FC3, alpha: 255));
    // Eyes, hair: out + 0.4 · (out − blur) · person.
    final detail = t(cv.subtract(out, t(cv.gaussianBlur(out, (0, 0), 1.5))));
    final p3 = t(cv.merge(cv.VecMat.fromList([p, p, p])));
    final sharp = t(cv.add(out, t(t(cv.multiply(detail, p3)).convertTo(cv.MatType.CV_32FC3, alpha: 0.4))));
    return sharp.convertTo(cv.MatType.CV_8UC3);
  } finally {
    for (final m in tmp) {
      m.dispose();
    }
  }
}

/// A face box for [person] (8-bit, 255 = person) when ML Kit gave none:
/// the middle of the head, from the person's top rows. Null when there's
/// no person.
(int, int, int, int)? faceBoxFromPerson(cv.Mat person) {
  final (h, w) = (person.rows, person.cols);
  final (_, bin) = cv.threshold(person, 127, 255, cv.THRESH_BINARY);
  final rows = cv.reduce(bin, 1, cv.REDUCE_MAX);
  bin.dispose();
  var top = -1;
  for (var y = 0; y < h; y++) {
    if (rows.at<int>(y, 0) > 0) {
      top = y;
      break;
    }
  }
  rows.dispose();
  if (top < 0) return null;
  // The head: from the top of the person, about a third of the photo down.
  final y0 = (top + 0.12 * h).round().clamp(0, h - 1);
  final y1 = (top + 0.38 * h).round().clamp(y0 + 1, h);
  final band = person.region(cv.Rect(0, y0, w, y1 - y0));
  final (_, bandBin) = cv.threshold(band, 127, 255, cv.THRESH_BINARY);
  final cols = cv.reduce(bandBin, 0, cv.REDUCE_MAX);
  bandBin.dispose();
  band.dispose();
  var left = -1;
  var right = -1;
  for (var x = 0; x < w; x++) {
    if (cols.at<int>(0, x) > 0) {
      if (left < 0) left = x;
      right = x;
    }
  }
  cols.dispose();
  if (left < 0) return null;
  final hw = right - left + 1;
  return ((left + 0.25 * hw).round(), y0, (right - 0.25 * hw).round().clamp((left + 0.25 * hw).round() + 1, w), y1);
}

/// [box] (x0, y0, x1, y1 fractions of the upright photo) where it lands in
/// the cropped and turned photo of size [size]: drawn into a mask of
/// [like]'s size and cropped like the photo.
(int, int, int, int)? _faceInCrop(List<double> box, cv.Mat like, PageEdits edits, (int, int) size) {
  if (box.length != 4) return null;
  final m = cv.Mat.zeros(like.rows, like.cols, cv.MatType.CV_8UC1);
  cv.rectangle(
    m,
    cv.Rect(
      (box[0] * like.cols).round(),
      (box[1] * like.rows).round(),
      math.max(1, ((box[2] - box[0]) * like.cols).round()),
      math.max(1, ((box[3] - box[1]) * like.rows).round()),
    ),
    cv.Scalar.all(255),
    thickness: -1,
  );
  final cropped = cropAndRotate(m, edits);
  disposeUnless(m, cropped);
  final sized = cv.resize(cropped, size, interpolation: cv.INTER_NEAREST);
  cropped.dispose();
  final (_, bin) = cv.threshold(sized, 127, 255, cv.THRESH_BINARY);
  sized.dispose();
  final rows = cv.reduce(bin, 1, cv.REDUCE_MAX);
  final cols = cv.reduce(bin, 0, cv.REDUCE_MAX);
  bin.dispose();
  int? first(cv.Mat v, int n, bool row, {bool last = false}) {
    for (var i = 0; i < n; i++) {
      final j = last ? n - 1 - i : i;
      if ((row ? v.at<int>(j, 0) : v.at<int>(0, j)) > 0) return j;
    }
    return null;
  }

  final (w, h) = size;
  final y0 = first(rows, h, true);
  final y1 = first(rows, h, true, last: true);
  final x0 = first(cols, w, false);
  final x1 = first(cols, w, false, last: true);
  rows.dispose();
  cols.dispose();
  if (x0 == null || y0 == null || x1 == null || y1 == null || x1 - x0 < 8 || y1 - y0 < 8) return null;
  return (x0, y0, x1 + 1, y1 + 1);
}

/// The long edge a passport photo is finished (enhanced, background
/// changed) at, at most.
const photoFinishLongEdge = 1600;

/// [enhancePhoto] then [replaceBackground] on [img] with [mask] (8-bit,
/// 255 = person, any size, or null). Returns [img] itself when neither
/// applies.
///
/// Round 11b, P1-14: Natural is [passportBrighten] after the background
/// (with the [face] box in [img]'s pixels, else one found from the mask);
/// Soft is the earlier soft touch-up ([enhancePhoto]) plus the same
/// brightening. Without a person mask there's nothing to brighten.
cv.Mat finishPhoto(
  cv.Mat img,
  cv.Mat? mask, {
  cv.Scalar? color,
  PhotoEnhance enhance = PhotoEnhance.off,
  (int, int, int, int)? face,
}) {
  var out = img;
  final sized = mask == null ? null : cv.resize(mask, (img.cols, img.rows), interpolation: cv.INTER_LINEAR);
  try {
    if (enhance == PhotoEnhance.smooth) out = enhancePhoto(img, sized, enhance);
    if (color != null && mask != null) {
      final backed = replaceBackground(out, mask, color);
      if (!identical(out, img)) out.dispose();
      out = backed;
    }
    if (enhance != PhotoEnhance.off && sized != null) {
      final box = face ?? faceBoxFromPerson(sized);
      if (box != null) {
        final bright = passportBrighten(out, sized, box);
        if (!identical(out, img)) out.dispose();
        out = bright;
      }
    }
    return out;
  } finally {
    sized?.dispose();
  }
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
/// Round 11b, K1: text is read from the enhanced page (Auto), at 1600 to
/// 2400 px on the long side — never a preview or a thumbnail. Low
/// resolution made ML Kit misread words ("eoonomies").
cv.Mat renderForOcr(String path, PageEdits edits) {
  final img = readUprightForCrop(path, edits.crop, 2400);
  final cropped = cropAndRotate(img, edits, maxLongEdge: 2400);
  disposeUnless(img, cropped);
  final long = math.max(cropped.cols, cropped.rows);
  final sized = long < 1600 ? cv.resize(cropped, (cropped.cols * 1600 ~/ long, cropped.rows * 1600 ~/ long), interpolation: cv.INTER_CUBIC) : cropped;
  disposeUnless(cropped, sized);
  final out = autoFilter(sized);
  sized.dispose();
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
      imported: capture == null,
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
cv.Mat _renderLook(
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
    timer?.lap('filter ${edits.filter.name} from auto base');
    return auto;
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

/// Round 11, P1-11: [findFingers] on the page's preview-size crop (the
/// Enhance work image, before any filter). Writes the mask to [maskOut]
/// (PNG) and returns its outlines, or null when no finger was found.
List<List<Pt>>? findFingersOnPage(
  String originalPath,
  PageEdits edits, {
  required String workPath,
  required int previewLongEdge,
  required String maskOut,
  StepTimer? timer,
}) {
  final work = _workImage(originalPath, edits, workPath, previewLongEdge, timer);
  try {
    final mask = findFingers(work);
    timer?.lap('find fingers');
    if (mask == null) return null;
    try {
      File(maskOut).parent.createSync(recursive: true);
      cv.imwrite(maskOut, mask);
      return fingerOutline(mask);
    } finally {
      mask.dispose();
    }
  } finally {
    work.dispose();
  }
}

/// Round 6, P0-2: Enhance's first image, before the page's cleaned base is
/// ready. The work image with the reference's instant bilateral clean-up
/// ([denoisePreview]) and the filter. Never the raw photo (except for the
/// `original` filter, which is the raw page by definition).
cv.Mat _renderInstantLook(
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
  final out = applyFilterFromClean(quick, edits.filter, cacheKey: '$workPath#instant');
  quick.dispose();
  timer?.lap('filter ${edits.filter.name}');
  return out;
}

/// Round 6, P0-2: Enhance's image once the cleaned base exists, from its
/// preview-size copy ([cleanPreviewPath]). The Auto result is cached at
/// [autoPath], so Colour Boost and Grayscale only add their last step.
cv.Mat _renderLookFromClean(
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
      final out = applyFilterFromClean(clean, edits.filter, cacheKey: cleanPreviewPath);
      timer?.lap('filter ${edits.filter.name}');
      return out;
    }
    final auto = _autoBase(clean, autoPath, timer, cleaned: true, cacheKey: cleanPreviewPath);
    timer?.lap('filter ${edits.filter.name} from auto');
    return auto;
  } finally {
    clean.dispose();
  }
}

/// Enhance's images get the same border clean-up (round 8, P0-7) and
/// finger removal (round 11) as the saved page, so what you see is what
/// prints.
cv.Mat renderLook(
  String originalPath,
  PageEdits edits, {
  required String workPath,
  required int previewLongEdge,
  String? autoBasePath,
  StepTimer? timer,
}) =>
    _finishLook(
      _renderLook(originalPath, edits, workPath: workPath, previewLongEdge: previewLongEdge, autoBasePath: autoBasePath, timer: timer),
      edits,
    );

/// See [renderLook].
cv.Mat renderInstantLook(
  String originalPath,
  PageEdits edits, {
  required String workPath,
  required int previewLongEdge,
  StepTimer? timer,
}) =>
    _finishLook(
      _renderInstantLook(originalPath, edits, workPath: workPath, previewLongEdge: previewLongEdge, timer: timer),
      edits,
    );

/// See [renderLook].
cv.Mat renderLookFromClean(
  String cleanPreviewPath,
  PageEdits edits, {
  String? autoPath,
  StepTimer? timer,
}) =>
    _finishLook(_renderLookFromClean(cleanPreviewPath, edits, autoPath: autoPath, timer: timer), edits);

cv.Mat _finishLook(cv.Mat look, PageEdits edits) => _withoutFingers(withCleanBorder(look, edits), edits);

/// [autoFilter] of [work] ([autoFrom] when [cleaned]), read from [path] if
/// an earlier look wrote it.
cv.Mat _autoBase(cv.Mat work, String path, StepTimer? timer, {bool cleaned = false, String? cacheKey}) {
  if (File(path).existsSync()) {
    final m = cv.imread(path, flags: cv.IMREAD_COLOR);
    if (!m.isEmpty) {
      timer?.lap('load auto base (cached)');
      return m;
    }
    m.dispose();
  }
  final auto = cleaned ? autoFrom(work, cacheKey: cacheKey) : autoFilter(work);
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
  int quality = 90,
  int thumbQuality = 80,
}) {
  final out = renderEdits(originalPath, edits, maxLongEdge: previewLongEdge);
  final thumb = fitLongEdge(out, thumbLongEdge);
  try {
    File(processedOut).parent.createSync(recursive: true);
    writeJpeg(out, processedOut, quality: quality);
    File(thumbOut).parent.createSync(recursive: true);
    writeJpeg(thumb, thumbOut, quality: thumbQuality);
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

/// Round 11 (footer in its own strip): [page] with a white strip
/// [stripFraction] of its height added underneath, and the footer badge
/// ([badge], BGRA, the height of its square) in it as in the PDF band:
/// the square 60 % of the strip high, right-aligned 60 % of the strip from
/// the right edge, centred top to bottom. Returns a new Mat.
cv.Mat stampFooter(cv.Mat page, cv.Mat badge, {double stripFraction = 0.04}) {
  final strip = math.max(12, (page.rows * stripFraction).round());
  final out = cv.Mat.fromScalar(page.rows + strip, page.cols, cv.MatType.CV_8UC3, cv.Scalar.all(255));
  final top = out.region(cv.Rect(0, 0, page.cols, page.rows));
  page.copyTo(top);
  top.dispose();
  const squareShare = PageFooter.squareMm / PageFooter.bandMm;
  var k = strip * squareShare / badge.rows;
  var margin = (strip * PageFooter.rightMm / PageFooter.bandMm).round();
  // A very narrow page: shrink the badge to fit.
  if (badge.cols * k + 2 * margin > page.cols) {
    k = (page.cols - 2 * margin) / badge.cols;
    if (k <= 0) return out;
  }
  final fw = math.max(1, (badge.cols * k).round());
  final fh = math.max(1, (badge.rows * k).round());
  margin = math.min(margin, page.cols - fw);
  final x = page.cols - margin - fw;
  final y = page.rows + ((strip - fh) / 2).round();
  final art = cv.resize(badge, (fw, fh), interpolation: k < 1 ? cv.INTER_AREA : cv.INTER_LINEAR);
  final ch = cv.split(art);
  final rgb = cv.merge(cv.VecMat.fromList([ch[0], ch[1], ch[2]]));
  final alpha = ch[3].convertTo(cv.MatType.CV_32FC1, alpha: 1 / 255);
  final alpha3 = cv.merge(cv.VecMat.fromList([alpha, alpha, alpha]));
  final roi = out.region(cv.Rect(x, y, fw, fh));
  final bgF = roi.convertTo(cv.MatType.CV_32FC3);
  final fgF = rgb.convertTo(cv.MatType.CV_32FC3);
  final ones = cv.Mat.fromScalar(fh, fw, cv.MatType.CV_32FC3, cv.Scalar.all(1));
  final inv = cv.subtract(ones, alpha3);
  final a = cv.multiply(fgF, alpha3);
  final b = cv.multiply(bgF, inv);
  final sum = cv.add(a, b);
  final blended = sum.convertTo(cv.MatType.CV_8UC3);
  blended.copyTo(roi);
  for (final m in [art, ...ch, rgb, alpha, alpha3, roi, bgF, fgF, ones, inv, a, b, sum, blended]) {
    m.dispose();
  }
  return out;
}

/// Round 11, section F (Reduce size): one picture made as small as
/// [maxBytes]. [boxW] × [boxH] ([exact]: cover-cropped to exactly that
/// size; else fitted inside) or [longSide] set the pixel size; then the quality goes
/// down (JPEG / WebP 92 … 40) and, when the size may change, the long edge
/// by 15 % steps down to [minEdge]. Written to [out] in its extension's
/// format, without any metadata (no location). Returns its size and whether
/// it fits; when nothing fits, [out] is the smallest version.
({int bytes, bool fits}) reduceImage(
  String src,
  String out, {
  required int maxBytes,
  int? boxW,
  int? boxH,
  bool exact = false,
  int? longSide,
  int minEdge = 800,
}) {
  var img = readUpright(src);
  try {
    if (boxW != null && boxH != null) {
      final sized = exact ? _cover(img, boxW, boxH) : _fitInside(img, boxW, boxH);
      disposeUnless(img, sized);
      img = sized;
    } else if (longSide != null) {
      final sized = fitLongEdge(img, longSide);
      disposeUnless(img, sized);
      img = sized;
    }
    final ext = out.split('.').last.toLowerCase();
    final png = ext == 'png';
    final qualities = png ? const [9] : const [92, 85, 80, 75, 70, 65, 60, 55, 50, 45, 40];
    cv.VecI32 params(int q) => cv.VecI32.fromList(switch (ext) {
      'png' => [cv.IMWRITE_PNG_COMPRESSION, q],
      'webp' => [cv.IMWRITE_WEBP_QUALITY, q],
      _ => [cv.IMWRITE_JPEG_QUALITY, q],
    });
    Uint8List encode(cv.Mat m, int q) {
      final ps = params(q);
      final (ok, bytes) = cv.imencode('.$ext', m, params: ps);
      ps.dispose();
      if (!ok) throw StateError('Could not encode .$ext');
      return bytes;
    }

    Uint8List? best;
    var edge = math.max(img.cols, img.rows);
    final floor = exact ? edge : math.min(edge, minEdge);
    var current = img;
    while (true) {
      for (final q in qualities) {
        final bytes = encode(current, q);
        if (best == null || bytes.length < best.length) best = bytes;
        if (bytes.length <= maxBytes) {
          File(out).writeAsBytesSync(bytes, flush: true);
          return (bytes: bytes.length, fits: true);
        }
      }
      if (exact || edge <= floor) break;
      edge = math.max(floor, (edge * 0.85).round());
      final next = fitLongEdge(img, edge);
      if (!identical(current, img)) current.dispose();
      current = next;
    }
    if (!identical(current, img)) current.dispose();
    File(out).writeAsBytesSync(best!, flush: true);
    return (bytes: best.length, fits: false);
  } finally {
    img.dispose();
  }
}

/// Exactly [w] × [h], the centre kept (scaled to cover, then cropped).
cv.Mat _cover(cv.Mat src, int w, int h) {
  final s = math.max(w / src.cols, h / src.rows);
  final sw = math.max(w, (src.cols * s).round());
  final sh = math.max(h, (src.rows * s).round());
  final scaled = cv.resize(src, (sw, sh), interpolation: s < 1 ? cv.INTER_AREA : cv.INTER_CUBIC);
  final roi = scaled.region(cv.Rect((sw - w) ~/ 2, (sh - h) ~/ 2, w, h));
  final out = roi.clone();
  roi.dispose();
  scaled.dispose();
  return out;
}

/// Inside [w] × [h], the shape kept; never enlarged. [src] itself when it
/// already fits.
cv.Mat _fitInside(cv.Mat src, int w, int h) {
  final s = math.min(w / src.cols, h / src.rows);
  if (s >= 1) return src;
  return cv.resize(src, (math.max(1, (src.cols * s).round()), math.max(1, (src.rows * s).round())), interpolation: cv.INTER_AREA);
}

/// Round 10, P1-8: a passport photo sheet as one picture (for a photo shop
/// or WhatsApp) at [dpi]: white [paperW] × [paperH] mm paper, each of
/// [items] (mm) showing `photos[photoOf[i]]`, and the same dashed cut lines
/// as the PDF along every photo edge, across the gaps.
cv.Mat photoSheetImage({
  required List<cv.Mat> photos,
  required List<int> photoOf,
  required List<({double x, double y, double w, double h})> items,
  required double paperW,
  required double paperH,
  required bool cutLines,
  int dpi = 300,
}) {
  double px(double mm) => mm / 25.4 * dpi;
  final sheet = cv.Mat.fromScalar(px(paperH).round(), px(paperW).round(), cv.MatType.CV_8UC3, cv.Scalar.all(255));
  for (final (i, it) in items.indexed) {
    final photo = photos[(i < photoOf.length ? photoOf[i] : 0).clamp(0, photos.length - 1)];
    final x = px(it.x).round();
    final y = px(it.y).round();
    final w = math.min(px(it.w).round(), sheet.cols - x);
    final h = math.min(px(it.h).round(), sheet.rows - y);
    if (w <= 0 || h <= 0) continue;
    final sized = cv.resize(photo, (w, h), interpolation: cv.INTER_AREA);
    final roi = sheet.region(cv.Rect(x, y, w, h));
    sized.copyTo(roi);
    sized.dispose();
    roi.dispose();
  }
  if (cutLines && items.isNotEmpty) {
    final xs = {for (final it in items) ...[it.x, it.x + it.w]}.toList()..sort();
    final ys = {for (final it in items) ...[it.y, it.y + it.h]}.toList()..sort();
    // 8 pt past the outer photos, 3 pt dashes, 2 pt gaps, grey 500.
    final over = px(8 * 25.4 / 72);
    final dash = px(3 * 25.4 / 72);
    final gap = px(2 * 25.4 / 72);
    final grey = cv.Scalar.all(0x9E);
    final t = math.max(1, px(0.4 * 25.4 / 72).round());
    void dashed(double x1, double y1, double x2, double y2) {
      final len = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
      if (len == 0) return;
      final dx = (x2 - x1) / len;
      final dy = (y2 - y1) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        final e = math.min(d + dash, len);
        cv.line(sheet, cv.Point((x1 + dx * d).round(), (y1 + dy * d).round()), cv.Point((x1 + dx * e).round(), (y1 + dy * e).round()), grey, thickness: t);
      }
    }

    for (final x in xs) {
      dashed(px(x), px(ys.first) - over, px(x), px(ys.last) + over);
    }
    for (final y in ys) {
      dashed(px(xs.first) - over, px(y), px(xs.last) + over, px(y));
    }
  }
  return sheet;
}
