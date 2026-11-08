import 'dart:async';

import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:injectable/injectable.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// How the phone is held, from the accelerometer (round 5, P0-1). The camera
/// UI is locked to portrait, so the camera plugin's orientation is always
/// portrait; gravity isn't. No permission is needed. Flat over a page keeps
/// the last confident pose (portrait until there is one).
@lazySingleton
class DeviceOrientationTracker {
  StreamSubscription<AccelerometerEvent>? _sub;
  int _users = 0;
  int _turns = 0;

  /// Clockwise quarter turns that bring a portrait capture upright.
  int get turns => _turns;

  void start() {
    if (_users++ > 0) return;
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        (e) => _turns = classifyGravity(e.x, e.y, _turns),
        // No sensor: stay on the last pose.
        onError: (Object _) {},
      );
    } on Object {
      _sub = null;
    }
  }

  void stop() {
    if (_users == 0 || --_users > 0) return;
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
