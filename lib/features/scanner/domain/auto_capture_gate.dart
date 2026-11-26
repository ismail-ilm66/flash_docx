import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Round 11, P1-8: when auto capture takes the photo. The page must be
/// found, its corners must move less than [still] of the frame width from
/// one outline to the next, and the phone must be still, for [hold]. After a
/// shot it waits for the page to change (outline lost, or the corners move
/// more than [newPage]) so the same page isn't taken twice.
class AutoCaptureGate {
  AutoCaptureGate({
    this.hold = const Duration(milliseconds: 800),
    this.still = 0.02,
    this.newPage = 0.15,
  });

  final Duration hold;
  final double still;
  final double newPage;

  Quad? _last;
  DateTime? _steadySince;
  Quad? _shotAt;

  /// How far the shutter ring is filled (0..1).
  double progress = 0;

  /// The latest outline ([q] null: no page), whether the phone is moving,
  /// and the frame's height per width (normalised y → width units). True
  /// when the photo should be taken now.
  bool update(Quad? q, {required bool moving, required DateTime now, double heightPerWidth = 16 / 9}) {
    final shotAt = _shotAt;
    if (shotAt != null) {
      // Waiting for another page.
      if (q == null || _move(q, shotAt, heightPerWidth) > newPage) _shotAt = null;
      _last = q;
      _steadySince = null;
      progress = 0;
      return false;
    }
    final last = _last;
    _last = q;
    if (q == null || moving || last == null || _move(q, last, heightPerWidth) >= still) {
      _steadySince = q == null || moving ? null : now;
      progress = 0;
      return false;
    }
    final since = _steadySince ??= now;
    progress = (now.difference(since).inMicroseconds / hold.inMicroseconds).clamp(0.0, 1.0);
    if (progress < 1) return false;
    _shotAt = q;
    _steadySince = null;
    progress = 0;
    return true;
  }

  /// A manual shot or a mode change: start over.
  void reset() {
    _last = null;
    _steadySince = null;
    _shotAt = null;
    progress = 0;
  }

  static double _move(Quad a, Quad b, double hpw) {
    var m = 0.0;
    final pa = a.points;
    final pb = b.points;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, math.max((pa[i].x - pb[i].x).abs(), (pa[i].y - pb[i].y).abs() * hpw));
    }
    return m;
  }
}
