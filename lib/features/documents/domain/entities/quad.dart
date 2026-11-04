import 'dart:math' as math;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'quad.freezed.dart';
part 'quad.g.dart';

/// A point in normalised image coordinates (0..1 on both axes).
@freezed
abstract class Pt with _$Pt {
  const factory Pt(double x, double y) = _Pt;
  const Pt._();

  factory Pt.fromJson(Map<String, dynamic> json) => _$PtFromJson(json);

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);

  double distanceTo(Pt o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  Pt clamp01() => Pt(x.clamp(0, 1), y.clamp(0, 1));
}

/// Document corners in normalised coordinates, ordered TL, TR, BR, BL.
@freezed
abstract class Quad with _$Quad {
  const factory Quad({
    required Pt tl,
    required Pt tr,
    required Pt br,
    required Pt bl,
  }) = _Quad;
  const Quad._();

  factory Quad.fromJson(Map<String, dynamic> json) => _$QuadFromJson(json);

  /// The whole image, optionally inset by [inset] (fraction of each edge).
  factory Quad.full({double inset = 0}) => Quad(
        tl: Pt(inset, inset),
        tr: Pt(1 - inset, inset),
        br: Pt(1 - inset, 1 - inset),
        bl: Pt(inset, 1 - inset),
      );

  /// Builds a quad from four points in any order by sorting them into
  /// TL, TR, BR, BL using the sum / difference trick.
  factory Quad.fromUnordered(List<Pt> pts) {
    assert(pts.length == 4, 'need 4 points');
    final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = bySum.first;
    final br = bySum.last;
    final rest = pts.where((p) => p != tl && p != br).toList()
      ..sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    // smaller (y - x) means further top-right.
    return Quad(tl: tl, tr: rest.first, br: br, bl: rest.last);
  }

  List<Pt> get points => [tl, tr, br, bl];

  Quad withPoint(int index, Pt p) => switch (index) {
        0 => copyWith(tl: p),
        1 => copyWith(tr: p),
        2 => copyWith(br: p),
        _ => copyWith(bl: p),
      };

  /// Approximate width / height of the warped output in normalised units
  /// (average of opposite edges).
  double get avgWidth => (tl.distanceTo(tr) + bl.distanceTo(br)) / 2;
  double get avgHeight => (tl.distanceTo(bl) + tr.distanceTo(br)) / 2;

  /// Shoelace area in normalised units.
  double get area {
    final p = points;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// True when the polygon is convex and non-self-intersecting.
  bool get isConvex {
    final p = points;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) continue;
      final s = cross.sign;
      if (sign == null) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  Quad clamp01() => Quad(
        tl: tl.clamp01(),
        tr: tr.clamp01(),
        br: br.clamp01(),
        bl: bl.clamp01(),
      );
}
