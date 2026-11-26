import 'dart:math' as math;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Port of the reference `LiveOutline` (round 11b, P0-15): smoothing and
/// stability for the camera outline and auto capture. Call [update] for
/// every analysed frame, with the time in seconds.
/// - the outline: corners move 30 % towards each new detection;
/// - shown after 2 frames in a row with a page, hidden after 4 without;
/// - stable when every corner stays within 2 % of the frame diagonal for
///   [hold] and the phone is still: a small wobble (2–5 %) pauses the
///   timer, a lasting one (> 0.4 s) is a new spot, a real move (> 5 %) or
///   a lost page starts again.
/// One addition for the app: after [shot], nothing is captured again
/// until the page is lost or really moves, so a page isn't taken twice.
class LiveOutline {
  LiveOutline(double frameW, double frameH, {this.hold = 0.8})
    : _w = frameW,
      _h = frameH,
      _diag = math.sqrt(frameW * frameW + frameH * frameH);

  final double hold;
  final double _w;
  final double _h;
  final double _diag;

  List<double>? _q; // pixels: x0, y0, … x3, y3
  int _hits = 0;
  int _miss = 0;
  List<double>? _anchor;
  double _tStill = 0;
  double _tPause = 0;
  double? _tLast;
  bool _waiting = false;

  ({Quad? outline, double progress, bool capture}) update(Quad? quad, double t, {bool phoneStill = true}) {
    final dt = _tLast == null ? 0.0 : math.max(0.0, t - _tLast!);
    _tLast = t;
    if (quad == null) {
      _miss++;
      _hits = 0;
      if (_miss >= 4) {
        _q = null;
        _anchor = null;
        _tStill = 0;
        _waiting = false;
      }
      return state;
    }
    _miss = 0;
    _hits++;
    final px = [for (final p in quad.points) ...[p.x * _w, p.y * _h]];
    final q = _q == null ? px : [for (var i = 0; i < 8; i++) _q![i] + 0.3 * (px[i] - _q![i])];
    _q = q;
    if (_anchor == null) {
      _anchor = [...q];
      _tStill = 0;
      return state;
    }
    var move = 0.0;
    for (var i = 0; i < 4; i++) {
      final dx = q[2 * i] - _anchor![2 * i];
      final dy = q[2 * i + 1] - _anchor![2 * i + 1];
      move = math.max(move, math.sqrt(dx * dx + dy * dy));
    }
    move /= _diag;
    if (move > 0.05) {
      // A real move: start again (and a new page may be taken).
      _anchor = [...q];
      _tStill = 0;
      _tPause = 0;
      _waiting = false;
    } else if (move <= 0.02 && phoneStill) {
      _tStill += dt;
      _tPause = 0;
    } else {
      // A wobble or the phone moving: pause, keeping the time counted …
      _tPause += dt;
      if (_tPause > 0.4 && phoneStill) {
        // … but a lasting offset is a new spot.
        _anchor = [...q];
        _tStill = 0;
        _tPause = 0;
      }
    }
    return state;
  }

  /// A photo was taken: wait for another page before the next one.
  void shot() {
    _waiting = true;
    _tStill = 0;
  }

  ({Quad? outline, double progress, bool capture}) get state {
    final q = _q;
    final shown = q != null && (_hits >= 2 || _miss > 0);
    final progress = !shown || _waiting ? 0.0 : math.min(1.0, _tStill / hold);
    return (
      outline: shown
          ? Quad(tl: Pt(q[0] / _w, q[1] / _h), tr: Pt(q[2] / _w, q[3] / _h), br: Pt(q[4] / _w, q[5] / _h), bl: Pt(q[6] / _w, q[7] / _h))
          : null,
      progress: progress,
      capture: progress >= 1.0,
    );
  }
}
