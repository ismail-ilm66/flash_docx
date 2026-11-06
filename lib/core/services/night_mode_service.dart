import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

/// Tells Android which theme the user picked, so the Android 12+ system
/// splash (drawn before Flutter starts) matches it on the next launch.
/// Older Android and iOS splashes can only follow the system setting.
@lazySingleton
class NightModeService {
  static const _channel = MethodChannel('com.flashdox.app/theme');

  Future<void> apply(ThemeMode mode) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setNightMode', mode.name);
    } on MissingPluginException {
      // Tests and hosts without the native side.
    } on PlatformException {
      // Best effort: the in-app theme is unaffected.
    }
  }
}
