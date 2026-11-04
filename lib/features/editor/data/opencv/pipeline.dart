// Pure OpenCV steps for the image pipeline. Each function is small and
// synchronous so it can be unit-tested on sample photos and run inside an
// isolate by `OpenCvImageProcessor`.
//
// All Mats are BGR 8-bit unless stated. Callers own the returned Mat.

import 'dart:math' as math;

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:opencv_dart/opencv.dart' as cv;

// ---------------------------------------------------------------------------
// Loading / sizing
// ---------------------------------------------------------------------------

/// Reads an image upright (EXIF orientation applied by OpenCV).
cv.Mat readUpright(String path) {
  final m = cv.imread(path, flags: cv.IMREAD_COLOR);
  if (m.isEmpty) {
    throw StateError('Could not decode $path');
  }
  return m;
}

/// Downscales so the long edge is at most [longEdge]. Returns the same Mat
/// (not a copy) when it is already small enough.
cv.Mat fitLongEdge(cv.Mat src, int longEdge) {
  final long = math.max(src.cols, src.rows);
  if (long <= longEdge) return src;
  final k = longEdge / long;
  final out = cv.resize(
    src,
    ((src.cols * k).round(), (src.rows * k).round()),
    interpolation: cv.INTER_AREA,
  );
  src.dispose();
  return out;
}

// ---------------------------------------------------------------------------
// Edge detection
// ---------------------------------------------------------------------------

/// Finds the largest 4-point contour covering more than [minAreaFraction] of
/// the image. Returns a normalised [Quad] or null.
Quad? detectDocumentQuad(
  cv.Mat bgr, {
  double minAreaFraction = 0.2,
  double? snapAspectRatio,
}) {
  final small = fitLongEdge(bgr.clone(), RenderPx.detectionLongEdge);
  final w = small.cols.toDouble();
  final h = small.rows.toDouble();
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final blurred = cv.gaussianBlur(gray, (5, 5), 0);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));

  Quad? best;
  var bestArea = 0.0;

  // Two passes with different Canny thresholds: tight for high-contrast
  // documents, loose for dim or low-contrast shots.
  for (final (lo, hi) in const [(50.0, 150.0), (20.0, 80.0)]) {
    final edges = cv.canny(blurred, lo, hi);
    final dilated = cv.dilate(edges, kernel, iterations: 2);
    final closed = cv.morphologyEx(dilated, cv.MORPH_CLOSE, kernel);
    final (contours, hierarchy) =
        cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    for (var i = 0; i < contours.length; i++) {
      final c = contours[i];
      final area = cv.contourArea(c);
      if (area < minAreaFraction * w * h || area <= bestArea) {
        continue;
      }
      final peri = cv.arcLength(c, true);
      final approx = cv.approxPolyDP(c, 0.02 * peri, true);
      if (approx.length == 4) {
        final pts = [
          for (var j = 0; j < 4; j++) Pt(approx[j].x / w, approx[j].y / h),
        ];
        final q = Quad.fromUnordered(pts);
        if (q.isConvex && _isReasonable(q)) {
          best = q;
          bestArea = area;
        }
      }
      approx.dispose();
    }
    contours.dispose();
    hierarchy.dispose();
    edges.dispose();
    dilated.dispose();
    closed.dispose();
    if (best != null) break;
  }

  kernel.dispose();
  blurred.dispose();
  gray.dispose();
  small.dispose();

  if (best == null) return null;
  if (snapAspectRatio != null) {
    best = snapQuadToAspect(best, snapAspectRatio, imageAspect: w / h);
  }
  return best.clamp01();
}

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

/// Adjusts the quad so its warped output has [aspect] (width / height),
/// keeping the centre and the dominant orientation. Used for ID card and
/// passport modes where the physical size is known.
Quad snapQuadToAspect(Quad q, double aspect, {required double imageAspect}) {
  // Work in pixel-like space so the ratio is meaningful.
  Pt toPx(Pt p) => Pt(p.x * imageAspect, p.y);
  Pt fromPx(Pt p) => Pt(p.x / imageAspect, p.y);
  final pts = q.points.map(toPx).toList();
  final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / 4;
  final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / 4;
  final avgW = (pts[0].distanceTo(pts[1]) + pts[3].distanceTo(pts[2])) / 2;
  final avgH = (pts[0].distanceTo(pts[3]) + pts[1].distanceTo(pts[2])) / 2;
  // Landscape card photographed in portrait → treat the longer side as width.
  final landscape = avgW >= avgH;
  final targetAspect = landscape ? aspect : 1 / aspect;
  // Keep the area, fix the ratio.
  final area = avgW * avgH;
  final newW = math.sqrt(area * targetAspect);
  final newH = newW / targetAspect;
  // Keep the current rotation angle of the top edge.
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

/// Perspective-warps [src] to [quad]. The output size follows the quad's
/// average edge lengths in source pixels, capped at [maxLongEdge].
cv.Mat warpToQuad(cv.Mat src, Quad quad, {int? maxLongEdge}) {
  final w = src.cols.toDouble();
  final h = src.rows.toDouble();
  cv.Point2f px(Pt p) => cv.Point2f(p.x * w, p.y * h);
  final tl = px(quad.tl);
  final tr = px(quad.tr);
  final br = px(quad.br);
  final bl = px(quad.bl);

  double dist(cv.Point2f a, cv.Point2f b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  var outW = math.max(dist(tl, tr), dist(bl, br));
  var outH = math.max(dist(tl, bl), dist(tr, br));
  if (maxLongEdge != null) {
    final long = math.max(outW, outH);
    if (long > maxLongEdge) {
      final k = maxLongEdge / long;
      outW *= k;
      outH *= k;
    }
  }
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
  final out = cv.warpPerspective(src, m, (ow, oh), flags: cv.INTER_CUBIC);
  m.dispose();
  srcPts.dispose();
  dstPts.dispose();
  return out;
}

cv.Mat rotateQuarterTurns(cv.Mat src, int quarterTurns) {
  final t = ((quarterTurns % 4) + 4) % 4;
  if (t == 0) return src;
  final code = switch (t) {
    1 => cv.ROTATE_90_CLOCKWISE,
    2 => cv.ROTATE_180,
    _ => cv.ROTATE_90_COUNTERCLOCKWISE,
  };
  final out = cv.rotate(src, code);
  src.dispose();
  return out;
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

/// Removes soft shadows by dividing each channel by a heavily blurred
/// estimate of the background.
cv.Mat removeShadows(cv.Mat bgr) {
  final channels = cv.split(bgr);
  final outChannels = <cv.Mat>[];
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (7, 7));
  final blurK = _oddKernel(math.max(bgr.cols, bgr.rows) ~/ 40);
  for (var i = 0; i < channels.length; i++) {
    final ch = channels[i];
    final dilated = cv.dilate(ch, kernel);
    final bg = cv.medianBlur(dilated, blurK);
    final norm = cv.divide(ch, bg, scale: 255);
    outChannels.add(norm);
    dilated.dispose();
    bg.dispose();
  }
  final merged = cv.merge(cv.VecMat.fromList(outChannels));
  for (final m in outChannels) {
    m.dispose();
  }
  channels.dispose();
  kernel.dispose();
  return merged;
}

int _oddKernel(int k) {
  final v = k.clamp(3, 51);
  return v.isOdd ? v : v + 1;
}

/// CLAHE on the L channel of Lab.
cv.Mat claheOnLuminance(cv.Mat bgr, {double clipLimit = 2.0}) {
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

/// Gentle gray-world white balance, blended at [strength] (0..1).
cv.Mat whiteBalance(cv.Mat bgr, {double strength = 0.5}) {
  final m = cv.mean(bgr);
  final avg = (m.val1 + m.val2 + m.val3) / 3;
  if (avg <= 0) return bgr.clone();
  final gains = [m.val1, m.val2, m.val3]
      .map((v) => v <= 0 ? 1.0 : 1 + strength * (avg / v - 1))
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

cv.Mat autoFilter(cv.Mat bgr) {
  final noShadow = removeShadows(bgr);
  final contrasty = claheOnLuminance(noShadow);
  final balanced = whiteBalance(contrasty);
  noShadow.dispose();
  contrasty.dispose();
  return balanced;
}

cv.Mat colorBoostFilter(cv.Mat bgr, {double saturation = 1.35}) {
  final auto = autoFilter(bgr);
  final hsv = cv.cvtColor(auto, cv.COLOR_BGR2HSV);
  final ch = cv.split(hsv);
  final s2 = cv.convertScaleAbs(ch[1], alpha: saturation);
  final merged = cv.merge(cv.VecMat.fromList([ch[0], s2, ch[2]]));
  final out = cv.cvtColor(merged, cv.COLOR_HSV2BGR);
  s2.dispose();
  merged.dispose();
  ch.dispose();
  hsv.dispose();
  auto.dispose();
  return out;
}

cv.Mat grayscaleFilter(cv.Mat bgr) {
  final auto = autoFilter(bgr);
  final gray = cv.cvtColor(auto, cv.COLOR_BGR2GRAY);
  final out = cv.cvtColor(gray, cv.COLOR_GRAY2BGR);
  auto.dispose();
  gray.dispose();
  return out;
}

/// Gray → adaptive Gaussian threshold → light denoise. Best for photocopies.
cv.Mat bwPrintFilter(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  final block = _oddKernel(math.max(gray.cols, gray.rows) ~/ 40);
  final bw = cv.adaptiveThreshold(
    gray,
    255,
    cv.ADAPTIVE_THRESH_GAUSSIAN_C,
    cv.THRESH_BINARY,
    block,
    10,
  );
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

/// Maps the -100..100 sliders onto `convertScaleAbs(alpha, beta)`.
/// contrast 100 → alpha 2.0, -100 → 0.25; brightness ±100 → beta ±100.
cv.Mat brightnessContrast(cv.Mat bgr, double brightness, double contrast) {
  if (brightness == 0 && contrast == 0) return bgr.clone();
  final c = contrast.clamp(-100, 100) / 100;
  final alpha = c >= 0 ? 1 + c : 1 + c * 0.75;
  final beta = brightness.clamp(-100, 100) * 1.0 + 128 * (1 - alpha);
  return cv.convertScaleAbs(bgr, alpha: alpha, beta: beta);
}

// ---------------------------------------------------------------------------
// Full render
// ---------------------------------------------------------------------------

/// Applies [edits] to the upright original at [path] and returns the result.
cv.Mat renderEdits(String path, PageEdits edits, {int? maxLongEdge}) {
  var img = readUpright(path);
  // 1. Perspective warp (or plain downscale when there is no crop).
  if (edits.crop != null) {
    final warped = warpToQuad(img, edits.crop!, maxLongEdge: maxLongEdge);
    img.dispose();
    img = warped;
  } else if (maxLongEdge != null) {
    img = fitLongEdge(img, maxLongEdge);
  }
  // 2. Rotate.
  img = rotateQuarterTurns(img, edits.quarterTurns);
  // 3. Filter.
  final filtered = applyFilter(img, edits.filter);
  img.dispose();
  // 4. Sliders.
  final out = brightnessContrast(filtered, edits.brightness, edits.contrast);
  filtered.dispose();
  return out;
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
