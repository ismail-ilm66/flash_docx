import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Pure geometry for the crop handles (round 3, P1-2). All points are in
/// screen pixels (dp) so angles and distances are true. Corner order TL, TR,
/// BR, BL; edge `e` runs from corner `e` to corner `e + 1`
/// (0 top, 1 right, 2 bottom, 3 left).
abstract final class CropGeometry {
  /// Neighbouring edges closer than this to parallel (sine of the angle,
  /// ≈ 6°) can't give a sensible intersection; the corner is translated
  /// along the edge normal instead.
  static const double _parallelSin = 0.1;

  /// Moves edge [edge] parallel to itself by the normal component of
  /// [delta]. Its two corners slide along the neighbouring edge lines.
  static List<Offset> moveEdge(List<Offset> q, int edge, Offset delta) {
    final a = q[edge];
    final b = q[(edge + 1) % 4];
    final dir = b - a;
    final len = dir.distance;
    if (len < 1e-6) return q;
    final n = Offset(-dir.dy / len, dir.dx / len);
    final shift = n * (delta.dx * n.dx + delta.dy * n.dy);
    return replaceEdge(q, edge, a + shift, b + shift, fallbackShift: shift);
  }

  /// Replaces edge [edge] with the line through [p1]–[p2] (a snapped
  /// candidate line); its corners become the intersections with the
  /// neighbouring edge lines.
  static List<Offset> replaceEdge(
    List<Offset> q,
    int edge,
    Offset p1,
    Offset p2, {
    Offset? fallbackShift,
  }) {
    final i = edge;
    final j = (edge + 1) % 4;
    final prevOther = q[(edge + 3) % 4]; // prev edge: prevOther → q[i]
    final nextOther = q[(edge + 2) % 4]; // next edge: q[j] → nextOther
    Offset solve(Offset corner, Offset other) {
      final hit = intersect(p1, p2, other, corner);
      if (hit != null) return hit;
      // Nearly parallel: move the corner straight across.
      return fallbackShift == null ? _project(corner, p1, p2) : corner + fallbackShift;
    }

    final out = [...q];
    out[i] = solve(q[i], prevOther);
    out[j] = solve(q[j], nextOther);
    return out;
  }

  /// Intersection of the infinite lines a1–a2 and b1–b2, or null when they
  /// are within ~6° of parallel.
  static Offset? intersect(Offset a1, Offset a2, Offset b1, Offset b2) {
    final r = a2 - a1;
    final s = b2 - b1;
    final denom = r.dx * s.dy - r.dy * s.dx;
    final lr = r.distance;
    final ls = s.distance;
    if (lr < 1e-9 || ls < 1e-9 || denom.abs() / (lr * ls) < _parallelSin) return null;
    final t = ((b1.dx - a1.dx) * s.dy - (b1.dy - a1.dy) * s.dx) / denom;
    return a1 + r * t;
  }

  static Offset _project(Offset p, Offset a, Offset b) {
    final d = b - a;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 < 1e-12) return a;
    final t = ((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / len2;
    return a + d * t;
  }

  /// Foot of the perpendicular from [p] to the infinite line a–b.
  static Offset project(Offset p, Offset a, Offset b) => _project(p, a, b);

  /// Distance from [p] to the infinite line a–b.
  static double distanceToLine(Offset p, Offset a, Offset b) => (p - _project(p, a, b)).distance;

  /// Smallest angle between two lines, in degrees (0..90).
  static double angleBetween(Offset a1, Offset a2, Offset b1, Offset b2) {
    final r = a2 - a1;
    final s = b2 - b1;
    final cos = (r.dx * s.dx + r.dy * s.dy).abs() / math.max(1e-9, r.distance * s.distance);
    return math.acos(cos.clamp(0.0, 1.0)) * 180 / math.pi;
  }

  /// True for a strictly convex quad in TL, TR, BR, BL order (clockwise on
  /// screen). A mirrored quad — an edge dragged past the opposite one — is
  /// rejected too.
  static bool isConvex(List<Offset> q) {
    for (var i = 0; i < 4; i++) {
      final a = q[i];
      final b = q[(i + 1) % 4];
      final c = q[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross <= 1e-9) return false;
    }
    return true;
  }
}
