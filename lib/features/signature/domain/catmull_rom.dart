import 'dart:ui';

/// Smooths a finger stroke (feature 4, Draw): a centripetal-free uniform
/// Catmull-Rom spline through the sampled points, [steps] segments between
/// each pair. The curve passes through every input point.
List<Offset> catmullRom(List<Offset> pts, {int steps = 6}) {
  if (pts.length < 3) return [...pts];
  final out = <Offset>[pts.first];
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 < pts.length ? i + 2 : pts.length - 1];
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      final t2 = t * t;
      final t3 = t2 * t;
      double c(double a, double b, double c, double d) =>
          0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      out.add(Offset(c(p0.dx, p1.dx, p2.dx, p3.dx), c(p0.dy, p1.dy, p2.dy, p3.dy)));
    }
  }
  return out;
}
