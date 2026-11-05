import 'dart:ui' show Offset;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/crop_geometry.dart';

/// Lines and corners found in the photo, in normalised coordinates
/// (round 3, P1-3). Computed once when Adjust edges opens.
class SnapCandidates {
  const SnapCandidates({this.lines = const [], this.corners = const []});

  final List<(Pt, Pt)> lines;
  final List<Pt> corners;

  bool get isEmpty => lines.isEmpty && corners.isEmpty;
}

/// Result of feeding a drag position through the [Snapper].
class SnapResult<T> {
  const SnapResult(this.value, {required this.snapped, required this.justSnapped});

  final T value;

  /// Currently held by a snap target.
  final bool snapped;

  /// A new snap target was acquired on this move: click + pulse.
  final bool justSnapped;
}

/// Magnetic corners and edges, in screen pixels (dp).
///
/// * A corner snaps to a candidate corner within 16 dp, else to the nearest
///   candidate line within 10 dp.
/// * An edge snaps to a candidate line within 12 dp and 8°.
/// * Moving more than 24 dp away breaks the snap.
class Snapper {
  Snapper(SnapCandidates c, Offset Function(Pt) toScreen)
      : _lines = [for (final (a, b) in c.lines) (toScreen(a), toScreen(b))],
        _corners = [for (final p in c.corners) toScreen(p)];

  static const double cornerToCorner = 16;
  static const double cornerToLine = 10;
  static const double edgeToLine = 12;
  static const double edgeMaxAngle = 8;
  static const double breakAway = 24;

  final List<(Offset, Offset)> _lines;
  final List<Offset> _corners;

  // Current hold (at most one of these).
  Offset? _heldCorner;
  (Offset, Offset)? _heldLine;

  void reset() {
    _heldCorner = null;
    _heldLine = null;
  }

  /// Snaps a dragged corner at raw finger position [p].
  SnapResult<Offset> corner(Offset p) {
    // Keep an existing hold until the finger moves 24 dp away.
    final hc = _heldCorner;
    if (hc != null) {
      if ((p - hc).distance <= breakAway) return SnapResult(hc, snapped: true, justSnapped: false);
      _heldCorner = null;
    }
    final hl = _heldLine;
    if (hl != null) {
      if (CropGeometry.distanceToLine(p, hl.$1, hl.$2) <= breakAway) {
        // Still allow upgrading to a corner on that line.
        final c = _nearestCorner(p);
        if (c != null) {
          _heldLine = null;
          _heldCorner = c;
          return SnapResult(c, snapped: true, justSnapped: true);
        }
        return SnapResult(CropGeometry.project(p, hl.$1, hl.$2), snapped: true, justSnapped: false);
      }
      _heldLine = null;
    }
    final c = _nearestCorner(p);
    if (c != null) {
      _heldCorner = c;
      return SnapResult(c, snapped: true, justSnapped: true);
    }
    final l = _nearestLine(p, cornerToLine);
    if (l != null) {
      _heldLine = l;
      return SnapResult(CropGeometry.project(p, l.$1, l.$2), snapped: true, justSnapped: true);
    }
    return SnapResult(p, snapped: false, justSnapped: false);
  }

  /// Snaps a dragged edge. [quad] already has the edge moved to the finger;
  /// returns the quad with the edge replaced by a candidate line if one is
  /// close and parallel enough.
  SnapResult<List<Offset>> edge(List<Offset> quad, int edge) {
    final a = quad[edge];
    final b = quad[(edge + 1) % 4];
    final mid = (a + b) / 2;
    final hl = _heldLine;
    if (hl != null) {
      if (CropGeometry.distanceToLine(mid, hl.$1, hl.$2) <= breakAway) {
        return SnapResult(CropGeometry.replaceEdge(quad, edge, hl.$1, hl.$2), snapped: true, justSnapped: false);
      }
      _heldLine = null;
    }
    (Offset, Offset)? best;
    var bestD = edgeToLine;
    for (final l in _lines) {
      if (CropGeometry.angleBetween(a, b, l.$1, l.$2) > edgeMaxAngle) continue;
      final d = CropGeometry.distanceToLine(mid, l.$1, l.$2);
      if (d <= bestD) {
        bestD = d;
        best = l;
      }
    }
    if (best == null) return SnapResult(quad, snapped: false, justSnapped: false);
    _heldLine = best;
    return SnapResult(CropGeometry.replaceEdge(quad, edge, best.$1, best.$2), snapped: true, justSnapped: true);
  }

  Offset? _nearestCorner(Offset p) {
    Offset? best;
    var bestD = cornerToCorner;
    for (final c in _corners) {
      final d = (c - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  (Offset, Offset)? _nearestLine(Offset p, double within) {
    (Offset, Offset)? best;
    var bestD = within;
    for (final l in _lines) {
      // Only near the segment itself (with a little slack), not its far
      // extension across the photo.
      if (!_nearSegment(p, l.$1, l.$2, slack: 24)) continue;
      final d = CropGeometry.distanceToLine(p, l.$1, l.$2);
      if (d <= bestD) {
        bestD = d;
        best = l;
      }
    }
    return best;
  }

  static bool _nearSegment(Offset p, Offset a, Offset b, {required double slack}) {
    final d = b - a;
    final len = d.distance;
    if (len < 1e-9) return false;
    final t = ((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / (len * len);
    return t * len >= -slack && t * len <= len + slack;
  }
}
