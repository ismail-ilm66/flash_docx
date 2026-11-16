import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

/// What kind of phone this is, for the low-RAM mode (round 6, P0-4). Read
/// once at start-up ([load]); until then, and if the platform can't say,
/// the phone counts as normal.
@lazySingleton
class DeviceProfile {
  static const _channel = MethodChannel('com.swtnoa.flashdox/device');

  /// At or below this much RAM the phone is treated as low-RAM. A "3 GB"
  /// phone reports ~2.8 GiB; a "4 GB" one (Y9 Prime 2019) ~3.6 GiB.
  static const int lowRamBytes = 3 * 1024 * 1024 * 1024;

  int? _totalBytes;
  bool _lowRamFlag = false;

  int? get totalBytes => _totalBytes;

  /// Android's `isLowRamDevice`, or ≤ 3 GB of RAM.
  bool get isLowRam => _lowRamFlag || (_totalBytes != null && _totalBytes! <= lowRamBytes);

  Future<void> load() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('memory');
      _totalBytes = (m?['totalBytes'] as num?)?.toInt();
      _lowRamFlag = m?['lowRam'] == true;
    } on MissingPluginException {
      // Tests and desktop: a normal phone.
    } on PlatformException {
      // Same.
    }
    if (!kReleaseMode) {
      debugPrint('[device] RAM ${_totalBytes == null ? '?' : '${(_totalBytes! / (1 << 20)).round()} MB'}; low-RAM mode ${isLowRam ? 'on' : 'off'}');
    }
  }

  /// For tests.
  @visibleForTesting
  void debugSet({int? totalBytes, bool lowRam = false}) {
    _totalBytes = totalBytes;
    _lowRamFlag = lowRam;
  }
}
