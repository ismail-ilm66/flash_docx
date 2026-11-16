import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

enum StorageLevel { ok, low, critical }

/// Free storage on the device (round 3, P0-C). Android: `StatFs`; iOS:
/// `volumeAvailableCapacityForImportantUsage`.
@lazySingleton
class StorageService {
  static const _channel = MethodChannel('com.swtnoa.flashdox/storage');

  /// Below this, warn: on the camera, and before saving (round 6, P0-3).
  static const int lowBytes = 200 * 1024 * 1024;

  /// Below this, block capture.
  static const int criticalBytes = 80 * 1024 * 1024;

  Future<int?> freeBytes() async {
    try {
      final v = await _channel.invokeMethod<int>('freeBytes');
      return v;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static StorageLevel levelFor(int? bytes) {
    if (bytes == null) return StorageLevel.ok;
    if (bytes < criticalBytes) return StorageLevel.critical;
    if (bytes < lowBytes) return StorageLevel.low;
    return StorageLevel.ok;
  }

  Future<StorageLevel> level() async => levelFor(await freeBytes());
}
