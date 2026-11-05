// Pure OpenCV steps for the image pipeline. Each function is small and
// synchronous so it can be unit-tested on sample photos and run inside an
// isolate by `OpenCvImageProcessor`.
//
// Ownership rule: a function never disposes a Mat it was given. It returns a
// new Mat the caller owns, or (where documented) the same Mat it received.

import 'dart:io';
import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
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
// Edge detection
// ---------------------------------------------------------------------------

class DetectionReport {
  const DetectionReport({
    required this.quad,
    required this.score,
    required this.elapsed,
    required this.strategy,
    required this.candidates,
  });

  /// Normalised corners, or null when nothing document-like was found.
  final Quad? quad;
  final double score;
  final Duration elapsed;

  /// Which pass produced the winner: `edges`, `otsu-gray`, `otsu-sat`, or `none`.
  final String strategy;
  final int candidates;

  bool get found => quad != null;

  @override
  String toString() =>
      'edges: ${found ? 'found' : 'none'} via $strategy score=${score.toStringAsFixed(3)} '
      'candidates=$candidates in ${elapsed.inMilliseconds} ms';
}

class _Candidate {
  _Candidate(this.quad, this.score, this.strategy);
  final Quad quad;
  final double score;
  final String strategy;
}

/// Finds the document in [bgr]. Two passes (edges + regions), every contour
/// considered, candidates scored by area × rectangularity (× aspect match when
/// [aspectHint] is given). Works on a ~1000 px copy.
DetectionReport detectDocument(
  cv.Mat bgr, {
  double minAreaFraction = 0.15,
  double? aspectHint,
}) {
  final sw = Stopwatch()..start();
  final small = fitLongEdge(bgr, RenderPx.detectionLongEdge);
  final w = small.cols.toDouble();
  final h = small.rows.toDouble();
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));

  final candidates = <_Candidate>[];

  // ---- Pass 1: edges, thresholds from the median brightness.
  final median = _medianOf(blurred);
  final lo = math.max(0.0, 0.66 * median);
  final hi = math.min(255.0, 1.33 * median);
  final edges = cv.canny(blurred, lo, hi);
  final closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
  final dilated = cv.dilate(closed, kernel);
  candidates.addAll(_collect(dilated, w, h, minAreaFraction, aspectHint, 'edges'));
  edges.dispose();
  closed.dispose();
  dilated.dispose();

  // ---- Pass 2: regions. Otsu on gray and on saturation (pale card on a dark
  // table, or a coloured card on a white desk).
  final (_, otsuGray) = cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
  final closedGray = cv.morphologyEx(otsuGray, cv.MORPH_CLOSE, kernel);
  candidates.addAll(_collect(closedGray, w, h, minAreaFraction, aspectHint, 'otsu-gray'));
  otsuGray.dispose();
  closedGray.dispose();

  final hsv = cv.cvtColor(small, cv.COLOR_BGR2HSV);
  final hsvCh = cv.split(hsv);
  final satBlur = cv.gaussianBlur(hsvCh[1], (5, 5), 0);
  final (_, otsuSat) = cv.threshold(satBlur, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
  final closedSat = cv.morphologyEx(otsuSat, cv.MORPH_CLOSE, kernel);
  candidates.addAll(_collect(closedSat, w, h, minAreaFraction, aspectHint, 'otsu-sat'));
  otsuSat.dispose();
  closedSat.dispose();
  satBlur.dispose();
  hsvCh.dispose();
  hsv.dispose();

  kernel.dispose();
  blurred.dispose();
  gray.dispose();
  disposeUnless(small, bgr);

  sw.stop();
  if (candidates.isEmpty) {
    return DetectionReport(
      quad: null,
      score: 0,
      elapsed: sw.elapsed,
      strategy: 'none',
      candidates: 0,
    );
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;
  return DetectionReport(
    quad: best.quad.clamp01(),
    score: best.score,
    elapsed: sw.elapsed,
    strategy: best.strategy,
    candidates: candidates.length,
  );
}

/// Convenience wrapper: just the quad (or null).
Quad? detectDocumentQuad(cv.Mat bgr, {double minAreaFraction = 0.15, double? snapAspectRatio}) {
  final r = detectDocument(bgr, minAreaFraction: minAreaFraction, aspectHint: snapAspectRatio);
  if (r.quad == null) return null;
  if (snapAspectRatio == null) return r.quad;
  return snapQuadToAspect(r.quad!, snapAspectRatio, imageAspect: bgr.cols / bgr.rows).clamp01();
}

double _medianOf(cv.Mat gray) {
  // Coarse histogram over a strided sample of the raw bytes; exact median
  // isn't needed. Reading `data` once avoids one native call per pixel.
  final hist = List<int>.filled(256, 0);
  final cont = gray.isContinuous ? gray : gray.clone();
  final data = cont.data;
  final step = math.max(1, data.length ~/ 50000);
  var n = 0;
  for (var i = 0; i < data.length; i += step) {
    hist[data[i]]++;
    n++;
  }
  if (!identical(cont, gray)) cont.dispose();
  var acc = 0;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc * 2 >= n) return v.toDouble();
  }
  return 128;
}

List<_Candidate> _collect(
  cv.Mat mask,
  double w,
  double h,
  double minAreaFraction,
  double? aspectHint,
  String strategy,
) {
  final out = <_Candidate>[];
  final (contours, hierarchy) = cv.findContours(mask, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
  final imageArea = w * h;
  for (var i = 0; i < contours.length; i++) {
    final c = contours[i];
    final area = cv.contourArea(c);
    final areaFrac = area / imageArea;
    if (areaFrac < minAreaFraction || areaFrac > 0.985) continue;

    final peri = cv.arcLength(c, true);
    final approx = cv.approxPolyDP(c, 0.02 * peri, true);
    Quad? quad;
    var shapePenalty = 1.0;
    if (approx.length == 4) {
      quad = _quadFrom(approx, w, h);
    } else if (approx.length >= 5 && approx.length <= 10) {
      // Rounded card corners / curled page: take the minimum-area rectangle.
      final box = cv.boxPoints(cv.minAreaRect(c));
      quad = Quad.fromUnordered([for (var j = 0; j < 4; j++) Pt(box[j].x / w, box[j].y / h)]);
      box.dispose();
      shapePenalty = 0.85;
    }
    approx.dispose();
    if (quad == null || !quad.isConvex || !_isReasonable(quad) || _isFrame(quad)) continue;

    // Rectangularity: contour area over its minimum-area rectangle.
    final box = cv.boxPoints(cv.minAreaRect(c));
    final bw = _dist(box[0], box[1]);
    final bh = _dist(box[1], box[2]);
    box.dispose();
    final rectArea = bw * bh;
    final rectangularity = rectArea <= 0 ? 0.0 : (area / rectArea).clamp(0.0, 1.0);

    var score = areaFrac * rectangularity * shapePenalty;
    if (aspectHint != null) {
      final long = math.max(bw, bh);
      final short = math.max(1e-6, math.min(bw, bh));
      final ratio = long / short;
      final target = aspectHint >= 1 ? aspectHint : 1 / aspectHint;
      final mismatch = math.log(ratio / target).abs();
      score *= 0.5 + 0.5 * (1 - mismatch.clamp(0.0, 1.0));
    }
    out.add(_Candidate(quad, score, strategy));
  }
  contours.dispose();
  hierarchy.dispose();
  return out;
}

double _dist(cv.Point2f a, cv.Point2f b) =>
    math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

Quad _quadFrom(cv.VecPoint approx, double w, double h) => Quad.fromUnordered([
      for (var j = 0; j < 4; j++) Pt(approx[j].x / w, approx[j].y / h),
    ]);

/// Rejects quads that are too thin or whose opposite edges differ wildly
/// (usually a shadow or a table edge, not a document).
bool _isReasonable(Quad q) {
  final top = q.tl.distanceTo(q.tr);
  final bottom = q.bl.distanceTo(q.br);
  final left = q.tl.distanceTo(q.bl);
  final right = q.tr.distanceTo(q.br);
  if (top < 0.1 || bottom < 0.1 || left < 0.1 || right < 0.1) return false;
  double ratio(double a, double b) => math.max(a, b) / math.max(1e-6, math.min(a, b));
  return ratio(top, bottom) < 2.5 && ratio(left, right) < 2.5;
}

/// The photo border itself (3+ corners on the image edge) is not a document.
bool _isFrame(Quad q) {
  bool onEdge(Pt p) => p.x < 0.01 || p.x > 0.99 || p.y < 0.01 || p.y > 0.99;
  return q.points.where(onEdge).length >= 3;
}

/// Adjusts the quad so its warped output has [aspect] (width / height),
/// keeping the centre and the dominant orientation. Used for ID card and
/// passport modes where the physical size is known.
Quad snapQuadToAspect(Quad q, double aspect, {required double imageAspect}) {
  Pt toPx(Pt p) => Pt(p.x * imageAspect, p.y);
  Pt fromPx(Pt p) => Pt(p.x / imageAspect, p.y);
  final pts = q.points.map(toPx).toList();
  final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / 4;
  final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / 4;
  final avgW = (pts[0].distanceTo(pts[1]) + pts[3].distanceTo(pts[2])) / 2;
  final avgH = (pts[0].distanceTo(pts[3]) + pts[1].distanceTo(pts[2])) / 2;
  final landscape = avgW >= avgH;
  final targetAspect = landscape ? aspect : 1 / aspect;
  final area = avgW * avgH;
  final newW = math.sqrt(area * targetAspect);
  final newH = newW / targetAspect;
  final angle = math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x);
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  Pt corner(double dx, double dy) =>
      Pt(cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
  final hw = newW / 2;
  final hh = newH / 2;
  return Quad(
    tl: fromPx(corner(-hw, -hh)),
    tr: fromPx(corner(hw, -hh)),
    br: fromPx(corner(hw, hh)),
    bl: fromPx(corner(-hw, hh)),
  );
}

// ---------------------------------------------------------------------------
// Warp / rotate
// ---------------------------------------------------------------------------

/// Perspective-warps [src] to [quad] at the quad's own resolution (average
/// edge length in source pixels). Never enlarges beyond that.
cv.Mat warpToQuad(cv.Mat src, Quad quad) {
  final w = src.cols.toDouble();
  final h = src.rows.toDouble();
  cv.Point2f px(Pt p) => cv.Point2f(p.x * w, p.y * h);
  final tl = px(quad.tl);
  final tr = px(quad.tr);
  final br = px(quad.br);
  final bl = px(quad.bl);
  final outW = math.max(_dist(tl, tr), _dist(bl, br));
  final outH = math.max(_dist(tl, bl), _dist(tr, br));
  final ow = math.max(1, outW.round());
  final oh = math.max(1, outH.round());

  final srcPts = cv.VecPoint2f.fromList([tl, tr, br, bl]);
  final dstPts = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(ow - 1.0, 0),
    cv.Point2f(ow - 1.0, oh - 1.0),
    cv.Point2f(0, oh - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(srcPts, dstPts);
  final out = cv.warpPerspective(src, m, (ow, oh), flags: cv.INTER_LINEAR);
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
  if (crop != null) step(warpToQuad(cur, crop));
  if (maxLongEdge != null) step(fitLongEdge(cur, maxLongEdge));
  step(rotateQuarterTurns(cur, edits.quarterTurns));
  return cur;
}

// ---------------------------------------------------------------------------
// Filters (all take a cropped BGR image, return a new Mat)
// ---------------------------------------------------------------------------

/// Light speckle removal.
cv.Mat denoise(cv.Mat bgr) => cv.medianBlur(bgr, 3);

/// Gray-world white balance blended at [strength], with gains clamped to
/// ±15% so a coloured document (a green card, a blue form) keeps its colour.
cv.Mat whiteBalance(cv.Mat bgr, {double strength = 0.5}) {
  final m = cv.mean(bgr);
  final avg = (m.val1 + m.val2 + m.val3) / 3;
  if (avg <= 0) return bgr.clone();
  final gains = [m.val1, m.val2, m.val3]
      .map((v) => v <= 0 ? 1.0 : (1 + strength * (avg / v - 1)).clamp(0.85, 1.15))
      .toList();
  final ch = cv.split(bgr);
  final scaled = <cv.Mat>[];
  for (var i = 0; i < 3; i++) {
    scaled.add(cv.convertScaleAbs(ch[i], alpha: gains[i]));
  }
  final out = cv.merge(cv.VecMat.fromList(scaled));
  for (final s in scaled) {
    s.dispose();
  }
  ch.dispose();
  return out;
}

/// Shadow correction: divide every channel by ONE blurred estimate of the
/// illumination (from luminance), so chroma is untouched. The divisor is
/// clamped at [floor] so dark regions aren't amplified into speckle, and the
/// result is blended with the input at [blend] (≤ 0.7).
cv.Mat removeShadows(cv.Mat bgr, {int floor = 40, double blend = 0.7}) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (7, 7));
  final blurK = _oddKernel(math.max(bgr.cols, bgr.rows) ~/ 40);
  final dilated = cv.dilate(gray, kernel);
  final bg = cv.medianBlur(dilated, blurK);
  final floorMat = cv.Mat.fromScalar(bgr.rows, bgr.cols, cv.MatType.CV_8UC1, cv.Scalar.all(floor.toDouble()));
  final bgClamped = cv.max(bg, floorMat);

  final channels = cv.split(bgr);
  final outChannels = <cv.Mat>[];
  for (var i = 0; i < channels.length; i++) {
    outChannels.add(cv.divide(channels[i], bgClamped, scale: 255));
  }
  final corrected = cv.merge(cv.VecMat.fromList(outChannels));
  final out = cv.addWeighted(corrected, blend, bgr, 1 - blend, 0);
  for (final m in outChannels) {
    m.dispose();
  }
  corrected.dispose();
  channels.dispose();
  bgClamped.dispose();
  floorMat.dispose();
  bg.dispose();
  dilated.dispose();
  kernel.dispose();
  gray.dispose();
  return out;
}

int _oddKernel(int k) {
  final v = k.clamp(3, 51);
  return v.isOdd ? v : v + 1;
}

/// Mild CLAHE on the L channel of Lab.
cv.Mat claheOnLuminance(cv.Mat bgr, {double clipLimit = 1.8}) {
  final lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
  final ch = cv.split(lab);
  final clahe = cv.createCLAHE(clipLimit: clipLimit, tileGridSize: (8, 8));
  final l2 = clahe.apply(ch[0]);
  final merged = cv.merge(cv.VecMat.fromList([l2, ch[1], ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_Lab2BGR);
  l2.dispose();
  merged.dispose();
  ch.dispose();
  lab.dispose();
  clahe.dispose();
  return out;
}

cv.Mat saturate(cv.Mat bgr, double factor) {
  final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
  final ch = cv.split(hsv);
  final s2 = cv.convertScaleAbs(ch[1], alpha: factor);
  final merged = cv.merge(cv.VecMat.fromList([ch[0], s2, ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_HSV2BGR);
  s2.dispose();
  merged.dispose();
  ch.dispose();
  hsv.dispose();
  return out;
}

/// Auto (colour, default): denoise → white balance → clamped shadow
/// correction → mild CLAHE → +10% saturation. Keeps stamps, logos and photos
/// in colour.
cv.Mat autoFilter(cv.Mat bgr) {
  final clean = denoise(bgr);
  final balanced = whiteBalance(clean);
  final noShadow = removeShadows(balanced);
  final contrasty = claheOnLuminance(noShadow);
  final out = saturate(contrasty, 1.10);
  clean.dispose();
  balanced.dispose();
  noShadow.dispose();
  contrasty.dispose();
  return out;
}

/// Auto + 25% saturation and a little contrast.
cv.Mat colorBoostFilter(cv.Mat bgr) {
  final auto = autoFilter(bgr);
  final sat = saturate(auto, 1.25);
  final out = cv.convertScaleAbs(sat, alpha: 1.1, beta: -12);
  auto.dispose();
  sat.dispose();
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

/// gray → normalise → adaptive threshold (block ≈ width / 40, odd; C 12) →
/// median 3. The only pure black-and-white filter.
cv.Mat bwPrintFilter(cv.Mat bgr) {
  final gray = _normalizedGray(bgr);
  final block = _oddKernel(gray.cols ~/ 40);
  final bw = cv.adaptiveThreshold(gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 12);
  final denoised = cv.medianBlur(bw, 3);
  final out = cv.cvtColor(denoised, cv.COLOR_GRAY2BGR);
  gray.dispose();
  bw.dispose();
  denoised.dispose();
  return out;
}

cv.Mat applyFilter(cv.Mat bgr, FilterType filter) => switch (filter) {
      FilterType.original => bgr.clone(),
      FilterType.auto => autoFilter(bgr),
      FilterType.colorBoost => colorBoostFilter(bgr),
      FilterType.grayscale => grayscaleFilter(bgr),
      FilterType.bwPrint => bwPrintFilter(bgr),
    };

/// Applies the brightness / contrast sliders as `a·x + b`, clamped to 0..255
/// (not `convertScaleAbs`, whose absolute value turned dark pixels grey when
/// brightness was negative). Same mapping as the live preview matrix.
cv.Mat brightnessContrast(cv.Mat bgr, PageEdits edits) {
  if (!edits.hasSliders) return bgr.clone();
  final t = edits.sliderTransform;
  return bgr.convertTo(cv.MatType.CV_8UC3, alpha: t.alpha, beta: t.beta);
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

/// Dedicated OCR image: crop + rotate at full resolution → gray → mild
/// contrast → light denoise. Never the user's chosen filter.
cv.Mat renderForOcr(String path, PageEdits edits) {
  final img = readUpright(path);
  final cropped = cropAndRotate(img, edits);
  disposeUnless(img, cropped);
  final gray = _normalizedGray(cropped);
  cropped.dispose();
  final clahe = cv.createCLAHE(clipLimit: 1.5, tileGridSize: (8, 8));
  final contrasty = clahe.apply(gray);
  final out = cv.medianBlur(contrasty, 3);
  clahe.dispose();
  gray.dispose();
  contrasty.dispose();
  return out;
}

/// Ingest: one decode per captured / imported photo. Writes the upright
/// original (long edge ≤ [maxOriginal]) and the editor's base preview, and
/// detects the document on that preview. Returns the detection report.
DetectionReport ingest({
  required String src,
  required String originalOut,
  required String previewOut,
  required int maxOriginal,
  required int previewLongEdge,
  double? aspectHint,
}) {
  final img = readUprightAtMost(src, maxOriginal);
  final capped = fitLongEdge(img, maxOriginal);
  final preview = fitLongEdge(capped, previewLongEdge);
  try {
    File(originalOut).parent.createSync(recursive: true);
    writeJpeg(capped, originalOut, quality: 95);
    File(previewOut).parent.createSync(recursive: true);
    writeJpeg(preview, previewOut, quality: 85);
    return detectDocument(preview, aspectHint: aspectHint);
  } finally {
    disposeUnless(preview, capped);
    disposeUnless(capped, img);
    img.dispose();
  }
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
    final img = readUpright(originalPath);
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
