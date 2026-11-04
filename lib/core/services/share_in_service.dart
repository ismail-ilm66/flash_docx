import 'dart:async';

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

/// Images shared *into* Flash Dox from other apps. Backed by a small
/// MethodChannel/EventChannel in `MainActivity.kt` on Android. On iOS this is
/// a no-op until a Share Extension target is added in Xcode.
@lazySingleton
class ShareInService {
  static const _method = MethodChannel('com.flashdox.app/share_in');
  static const _events = EventChannel('com.flashdox.app/share_in/events');

  /// Paths shared while the app was closed (consumed once).
  Future<List<String>> initialShare() async {
    try {
      final r = await _method.invokeMethod<List<dynamic>>('getInitialShare');
      return r?.cast<String>() ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Paths shared while the app is running.
  Stream<List<String>> get shares => _events
      .receiveBroadcastStream()
      .map((e) => (e as List<dynamic>).cast<String>())
      .handleError((_) {});
}
