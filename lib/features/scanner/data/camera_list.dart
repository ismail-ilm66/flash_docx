import 'dart:async';

import 'package:camera/camera.dart';

/// Round 10, P0-2: the device's cameras, looked up once at app start so the
/// camera screen only has to open one.
abstract final class CameraList {
  static Future<List<CameraDescription>>? _cameras;

  static Future<List<CameraDescription>> get() {
    final f = _cameras ??= availableCameras();
    // A failed lookup (no permission yet, a plugin hiccup) is tried again
    // next time.
    f.catchError((Object _) {
      if (identical(_cameras, f)) _cameras = null;
      return const <CameraDescription>[];
    }).ignore();
    return f;
  }

  /// Starts the lookup; errors are left for [get] to report.
  static void preload() => get().ignore();
}
