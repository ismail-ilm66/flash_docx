// Pure OpenCV steps for the image pipeline. Each function is small and
// synchronous so it can be unit-tested on sample photos and run inside an
// isolate by `OpenCvImageProcessor`.
//
// Ownership rule: a function never disposes a Mat it was given. It returns a
// new Mat the caller owns, or (where documented) the same Mat it received.

import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:opencv_dart/opencv.dart' as cv;

// ---------------------------------------------------------------------------
// Loading / sizing
// ---------------------------------------------------------------------------

/// Reads an image upright (EXIF orientation applied by OpenCV).
cv.Mat readUpright(String path, {int flags = cv.IMREAD_COLOR}) {
  final m = cv.imread(path, flags: flags);
  if (m.isEmpty) {
    m.dispose();
    throw StateError('Could not decode $path');
  }
  return m;
}

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
      final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
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
    small = cv.resize(bgr, ((wFull * scale).toInt(), (hFull * scale).toInt()), interpolation: cv.INTER_AREA);
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
    final (contours, hierarchy) = cv.findContours(map, retr, cv.CHAIN_APPROX_SIMPLE);
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
      final onBorder = q.where((p) => p.x < m || p.y < m || p.x > w - 1 - m || p.y > h - 1 - m).length;
      if (onBorder >= 3) continue;
      final rect = cornerAnglesScore(q);
      if (rect < 0.55) continue;
      final solidity = math.min(1.0, area / math.max(1.0, qa));
      var score = math.sqrt(frac) * rect * (0.5 + 0.5 * solidity);
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
    return const DetectionReport(quad: null, score: 0, elapsed: Duration.zero, strategy: 'none', candidates: 0);
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
  final closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, k, iterations: 2);
  final dil = cv.dilate(closed, k);
  // Close shapes that run off the photo (page partly outside the frame).
  cv.rectangle(dil, cv.Rect(0, 0, dil.cols, dil.rows), cv.Scalar.all(255), thickness: 2);
  maps.add(('edges', dil));
  for (final x in [blur, edges, closed]) {
    x.dispose();
  }

  final k2 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  cv.Mat regions(cv.Mat channel, int type) {
    final b = cv.gaussianBlur(channel, (7, 7), 0);
    final (_, th) = cv.threshold(b, 0, 255, type | cv.THRESH_OTSU);
    final opened = cv.morphologyEx(th, cv.MORPH_OPEN, k2);
    final out = cv.morphologyEx(opened, cv.MORPH_CLOSE, k2, iterations: 2);
    for (final x in [b, th, opened]) {
      x.dispose();
    }
    return out;
  }

  // B) Pale paper / card on a darker surface.
  final labCh = cv.split(lab);
  maps.add(('bright', regions(labCh[0], cv.THRESH_BINARY)));
  labCh.dispose();
  // C) White / grey paper on a colourful surface.
  final hsvCh = cv.split(hsv);
  maps.add(('lowsat', regions(hsvCh[1], cv.THRESH_BINARY_INV)));
  hsvCh.dispose();

  for (final x in [gray, lab, hsv, k, k2]) {
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
        final pts = [for (var j = 0; j < 4; j++) (x: approx[j].x.toDouble(), y: approx[j].y.toDouble())];
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
    final n = math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y) + 1e-6;
    sum += ((v1x * v2x + v1y * v2y) / n).abs();
  }
  return math.max(0.0, 1.0 - 2.0 * sum / 4);
}

double quadAspect(List<XY> q) {
  double d(XY a, XY b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
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
({List<(Pt, Pt)> lines, List<Pt> corners}) snapCandidates(cv.Mat bgr, {double? aspectHint}) {
  final s = math.min(1.0, kDetectLongEdge / math.max(bgr.rows, bgr.cols));
  final small = s < 1
      ? cv.resize(bgr, ((bgr.cols * s).toInt(), (bgr.rows * s).toInt()), interpolation: cv.INTER_AREA)
      : bgr.clone();
  final w = small.cols.toDouble();
  final h = small.rows.toDouble();
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final blur = cv.gaussianBlur(gray, (5, 5), 0);
  final m = medianOf(blur);
  final edges = cv.canny(blur, math.max(10.0, 0.66 * m), math.min(255.0, math.max(40.0, 1.33 * m)));
  final minLen = 0.08 * math.min(w, h);
  final raw = cv.HoughLinesP(edges, 1, math.pi / 180, 40, minLineLength: minLen, maxLineGap: 10);
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

  final merged = mergeSegments(segs).where((l) => _len(l.$1, l.$2) >= minLen).toList()
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
      if (p.x < -0.02 * w || p.y < -0.02 * h || p.x > 1.02 * w || p.y > 1.02 * h) continue;
      if (_distToSegment(p, a1, a2) > near || _distToSegment(p, b1, b2) > near) continue;
      corners.add(p);
    }
  }
  small.dispose();

  // Corners of the best detection candidates (already normalised).
  final det = detectDocument(bgr, aspectHint: aspectHint);
  final out = <Pt>[for (final q in det.ranked) ...q.points];
  for (final c in corners) {
    final n = Pt(c.x / w, c.y / h).clamp01();
    if (out.every((o) => (o.x - n.x).abs() * w > 6 || (o.y - n.y).abs() * h > 6)) out.add(n);
  }
  return (
    lines: [for (final (a, b) in lines) (Pt(a.x / w, a.y / h), Pt(b.x / w, b.y / h))],
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
        final longest = g.reduce((a, b) => _len(a.$1, a.$2) >= _len(b.$1, b.$2) ? a : b);
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
        return ((x: a.x + dx * tMin, y: a.y + dy * tMin), (x: a.x + dx * tMax, y: a.y + dy * tMax));
      }(),
  ];
}

double _len(XY a, XY b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

double _angleDeg(XY a1, XY a2, XY b1, XY b2) {
  final rx = a2.x - a1.x;
  final ry = a2.y - a1.y;
  final sx = b2.x - b1.x;
  final sy = b2.y - b1.y;
  final cos = (rx * sx + ry * sy).abs() / math.max(1e-9, _len(a1, a2) * _len(b1, b2));
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
  final q = orderCorners([for (final p in quad.points) (x: p.x * w, y: p.y * h)]);
  double d(XY a, XY b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  var wt = math.max(d(q[2], q[3]), d(q[1], q[0])).toInt();
  var ht = math.max(d(q[1], q[2]), d(q[0], q[3])).toInt();
  if (aspect != null) {
    if (wt >= ht) {
      ht = (wt / aspect).round();
    } else {
      wt = (ht / aspect).round();
    }
  }
  wt = math.max(1, wt);
  ht = math.max(1, ht);
  final srcPts = cv.VecPoint2f.fromList([for (final p in q) cv.Point2f(p.x, p.y)]);
  final dstPts = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(wt - 1.0, 0),
    cv.Point2f(wt - 1.0, ht - 1.0),
    cv.Point2f(0, ht - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(srcPts, dstPts);
  final out = cv.warpPerspective(src, m, (wt, ht), flags: cv.INTER_CUBIC, borderMode: cv.BORDER_REPLICATE);
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
  // Keep ≥2× the target in the source so the final INTER_AREA shrink does
  // the quality work; exports (standard/full) pass through at full size.
  if (maxLongEdge != null &&
      crop != null &&
      crop.area < 0.9 &&
      math.max(src.cols, src.rows) > maxLongEdge * 2) {
    step(fitLongEdge(cur, maxLongEdge * 2));
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

/// Gray-world white balance, blended at [strength].
cv.Mat grayWorldWb(cv.Mat bgr, double strength) {
  final m = cv.mean(bgr);
  final means = [m.val1, m.val2, m.val3];
  final avg = (means[0] + means[1] + means[2]) / 3;
  final ch = cv.split(bgr);
  final scaled = <cv.Mat>[
    for (var i = 0; i < 3; i++)
      ch[i].convertTo(cv.MatType.CV_8UC1, alpha: 1 + (avg / math.max(means[i], 1.0) - 1) * strength, beta: _trunc),
  ];
  final out = cv.merge(cv.VecMat.fromList(scaled));
  for (final s in scaled) {
    s.dispose();
  }
  ch.dispose();
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

/// Non-local-means denoise on a ≤ 2000 px copy; for larger inputs the fine
/// detail of the original (minus its noise-scale blur) is added back.
cv.Mat denoise(cv.Mat bgr) {
  final h = bgr.rows;
  final w = bgr.cols;
  final s = math.min(1.0, 2000.0 / math.max(h, w));
  final small = s < 1
      ? cv.resize(bgr, ((w * s).toInt(), (h * s).toInt()), interpolation: cv.INTER_AREA)
      : bgr;
  cv.Mat clean;
  try {
    clean = cv.fastNlMeansDenoisingColored(small, h: 5, hColor: 5, templateWindowSize: 7, searchWindowSize: 21);
  } catch (_) {
    clean = cv.bilateralFilter(small, 7, 40, 40);
  }
  if (s >= 1) return clean;
  small.dispose();
  final up = cv.resize(clean, (w, h), interpolation: cv.INTER_CUBIC);
  clean.dispose();
  final blur = cv.gaussianBlur(bgr, (0, 0), 1.5);
  final detail = cv.subtract(bgr, blur, dtype: cv.MatType.CV_16S);
  final half = detail.convertTo(cv.MatType.CV_16SC3, alpha: 0.5);
  final up16 = up.convertTo(cv.MatType.CV_16SC3);
  final sum = cv.add(up16, half);
  final out = sum.convertTo(cv.MatType.CV_8UC3);
  for (final x in [up, blur, detail, half, up16, sum]) {
    x.dispose();
  }
  return out;
}

/// Paper brightness (illumination) without the text, as float32, same size.
cv.Mat background(cv.Mat ch8) {
  final h = ch8.rows;
  final w = ch8.cols;
  final s = 400.0 / math.max(h, w);
  final small = cv.resize(ch8, (math.max(1, (w * s).toInt()), math.max(1, (h * s).toInt())), interpolation: cv.INTER_AREA);
  final k = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  final dil = cv.dilate(small, k);
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
cv.Mat _normalizeIllumination(cv.Mat ch8, {required double scale, double blend = 1.0}) {
  final bg = background(ch8);
  final floor = cv.Mat.fromScalar(bg.rows, bg.cols, cv.MatType.CV_32FC1, cv.Scalar.all(40));
  final bgc = cv.max(bg, floor);
  final f = ch8.convertTo(cv.MatType.CV_32FC1);
  final norm = cv.divide(f, bgc, scale: scale);
  final mixed = blend >= 1 ? norm : cv.addWeighted(norm, blend, f, 1 - blend, 0);
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
  final l2 = ch[0].convertTo(cv.MatType.CV_8UC1, alpha: k, beta: -lo * k + _trunc);
  final merged = cv.merge(cv.VecMat.fromList([l2, ch[1], ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_Lab2BGR);
  for (final x in [l2, merged, lab]) {
    x.dispose();
  }
  ch.dispose();
  return out;
}

/// "Auto (colour)": clean, bright page, colours kept. For paper documents.
cv.Mat autoFilter(cv.Mat bgr) {
  final dn = denoise(bgr);
  final wb = grayWorldWb(dn, 0.6);
  dn.dispose();
  final ch = cv.split(wb);
  final norm = [for (var i = 0; i < 3; i++) _normalizeIllumination(ch[i], scale: 245, blend: 0.75)];
  ch.dispose();
  wb.dispose();
  final merged = cv.merge(cv.VecMat.fromList(norm));
  for (final n in norm) {
    n.dispose();
  }
  final lv = levelsL(merged, 1, 99.5); // global contrast; CLAHE here caused banding
  merged.dispose();
  final sat = saturate(lv, 1.10);
  lv.dispose();
  final out = unsharp(sat, 0.35, 1.2);
  sat.dispose();
  return out;
}

/// "ID colour" (default in ID / passport): no background whitening — a card
/// is not white paper. Clean, sharp, true colours.
cv.Mat idColorFilter(cv.Mat bgr) {
  final dn = denoise(bgr);
  final wb = grayWorldWb(dn, 0.5);
  dn.dispose();
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
  final bw = cv.adaptiveThreshold(norm, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 12);
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
  final gray = _normalizedGray(auto);
  final out = cv.cvtColor(gray, cv.COLOR_GRAY2BGR);
  auto.dispose();
  gray.dispose();
  return out;
}

/// Auto + 25 % saturation and a little contrast.
cv.Mat colorBoostFilter(cv.Mat bgr) {
  final auto = autoFilter(bgr);
  final sat = saturate(auto, 1.25);
  final out = sat.convertTo(cv.MatType.CV_8UC3, alpha: 1.1, beta: -12);
  auto.dispose();
  sat.dispose();
  return out;
}

cv.Mat applyFilter(cv.Mat bgr, FilterType filter) => switch (filter) {
      FilterType.original => bgr.clone(),
      FilterType.auto => autoFilter(bgr),
      FilterType.idColor => idColorFilter(bgr),
      FilterType.colorBoost => colorBoostFilter(bgr),
      FilterType.grayscale => grayscaleFilter(bgr),
      FilterType.bwPrint => bwPrintFilter(bgr),
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

/// Variance of the Laplacian on a 1000 px copy (reference `sharpness()`), and
/// the mean brightness of that copy. Low sharpness = blurry; low brightness =
/// dark. Thresholds live in `CaptureChecks`.
({double sharpness, double brightness}) captureStats(cv.Mat bgr) {
  final s = 1000.0 / math.max(bgr.rows, bgr.cols);
  final small = cv.resize(bgr, ((bgr.cols * s).toInt(), (bgr.rows * s).toInt()));
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
cv.Mat renderEdits(String path, PageEdits edits, {int? maxLongEdge}) {
  final img = readUpright(path);
  final cropped = cropAndRotate(img, edits, maxLongEdge: maxLongEdge);
  disposeUnless(img, cropped);
  final filtered = applyFilter(cropped, edits.filter);
  cropped.dispose();
  final out = brightnessContrast(filtered, edits);
  filtered.dispose();
  return out;
}

/// One card side for print (P1-9): from the original, cropped and warped to
/// the real card shape, filtered, then shrunk with area averaging to the
/// pixel size for [dpi] at [widthMm] × [heightMm] — never above the photo's
/// own resolution. Always landscape (portrait renders are turned).
cv.Mat renderCard(
  String originalPath,
  PageEdits edits, {
  required double widthMm,
  required double heightMm,
  required int dpi,
}) {
  final full = renderEdits(originalPath, edits);
  var card = full;
  if (card.rows > card.cols) {
    card = cv.rotate(full, cv.ROTATE_90_COUNTERCLOCKWISE);
    full.dispose();
  }
  final tw = (widthMm / 25.4 * dpi).round();
  final th = (heightMm / 25.4 * dpi).round();
  if (card.cols <= tw) return card; // native resolution is lower: keep it
  final out = cv.resize(card, (tw, th), interpolation: cv.INTER_AREA);
  card.dispose();
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
  });

  final DetectionReport detection;

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
}) {
  final header = jpegSize(src);
  final (img, scale) = _decodeForPreview(src, previewLongEdge, header);
  final preview = fitLongEdge(img, previewLongEdge);
  try {
    File(previewOut).parent.createSync(recursive: true);
    writeJpeg(preview, previewOut, quality: 85);
    final detection = detectDocument(preview, aspectHint: aspectHint, searchArea: searchArea);
    final stats = captureStats(preview);
    // EXIF may swap the header's width and height; the decoded image is
    // upright, so take the orientation from it.
    final long = header == null ? math.max(img.cols, img.rows) * scale : math.max(header.width, header.height);
    final short = header == null ? math.min(img.cols, img.rows) * scale : math.min(header.width, header.height);
    final landscape = img.cols >= img.rows;
    return IngestReport(
      detection: detection,
      sharpness: stats.sharpness,
      brightness: stats.brightness,
      width: landscape ? long : short,
      height: landscape ? short : long,
      decodeScale: scale,
    );
  } finally {
    disposeUnless(preview, img);
    img.dispose();
  }
}

(cv.Mat, int) _decodeForPreview(String src, int target, ({int width, int height})? header) {
  const flagsByScale = {1: cv.IMREAD_COLOR, 2: cv.IMREAD_REDUCED_COLOR_2, 4: cv.IMREAD_REDUCED_COLOR_4, 8: cv.IMREAD_REDUCED_COLOR_8};
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
cv.Mat renderLook(String originalPath, PageEdits edits, {required String workPath, required int previewLongEdge}) {
  final cached = File(workPath).existsSync();
  final cv.Mat work;
  if (cached) {
    work = readUpright(workPath);
  } else {
    final img = readUprightAtMost(originalPath, previewLongEdge * 2);
    final cropped = cropAndRotate(img, edits, maxLongEdge: previewLongEdge);
    if (identical(cropped, img)) {
      work = img;
    } else {
      img.dispose();
      work = cropped;
    }
    File(workPath).parent.createSync(recursive: true);
    writeJpeg(work, workPath, quality: 92);
  }
  final out = applyFilter(work, edits.filter);
  work.dispose();
  return out;
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
    isPng ? [cv.IMWRITE_PNG_COMPRESSION, 3] : [cv.IMWRITE_JPEG_QUALITY, quality],
  );
  final ok = cv.imwrite(path, img, params: params);
  params.dispose();
  if (!ok) throw StateError('Could not write $path');
}
