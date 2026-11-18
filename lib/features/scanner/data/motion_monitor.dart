import 'dart:math' as math;

/// One gyroscope reading: rotation rates (rad/s) and when it was taken.
typedef GyroSample = ({double x, double y, double z, DateTime at});

/// Round 7, P0-1: the gyroscope only drives a "Hold still" hint on the
/// preview, before the tap. It never holds the shutter back (round 6 made
/// the shutter wait up to 1 s; users moved the phone, thinking the photo
/// was taken).
class MotionMonitor {
  /// Clearly moving: at or over this rotation rate…
  static const double movingRate = 0.3;

  /// …and still again once it stays under this one…
  static const double stillRate = 0.15;

  /// …for this long.
  static const Duration settle = Duration(milliseconds: 300);

  bool _moving = false;
  DateTime? _stillSince;
  bool _movedSinceFocus = true;

  /// The phone is moving: show the hint.
  bool get isMoving => _moving;

  /// Adds a reading; true when [isMoving] changed.
  bool add(GyroSample s) {
    final rate = math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
    if (rate >= movingRate) {
      _stillSince = null;
      _movedSinceFocus = true;
      if (_moving) return false;
      _moving = true;
      return true;
    }
    if (!_moving) return false;
    if (rate >= stillRate) {
      _stillSince = null;
      return false;
    }
    final since = _stillSince ??= s.at;
    if (s.at.difference(since) < settle) return false;
    _moving = false;
    _stillSince = null;
    return true;
  }

  /// Whether focus should go back to the page: the phone moved since the
  /// last time (or focus was never set) and it isn't moving now. Re-aiming
  /// a phone that hasn't moved only makes the lens hunt.
  bool takeFocusRefresh() {
    if (_moving || !_movedSinceFocus) return false;
    _movedSinceFocus = false;
    return true;
  }
}
