import 'dart:io';

import 'package:flash_dox/features/splash/presentation/splash_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1-1: one splash. The Flutter splash must draw the same file, at the same
/// size, as `flutter_native_splash` (treated as 4x → 288 dp).
void main() {
  test('Flutter splash uses the native splash image at 288 dp', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final section = pubspec.substring(pubspec.indexOf('flutter_native_splash:\n  color'));
    final images = RegExp(r'image: (\S+)').allMatches(section).map((m) => m.group(1)).take(2).toList();
    expect(images, [SplashPage.markAsset, SplashPage.markSize == 288 ? SplashPage.markAsset : 'size mismatch']);
    expect(File(SplashPage.markAsset).existsSync(), isTrue);
    expect(SplashPage.markSize, 1152 / 4);
  });
}
