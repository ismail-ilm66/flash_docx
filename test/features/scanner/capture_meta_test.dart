import 'dart:math' as math;

import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('captureRotation (P0-1 table)', () {
    const back = CaptureMeta(sensorOrientation: 90, deviceTurns: 0);
    CaptureMeta held(int turns, {bool front = false}) =>
        CaptureMeta(sensorOrientation: front ? 270 : 90, deviceTurns: turns, frontCamera: front);

    test('tagged photos: the tag is applied elsewhere, then how it was held', () {
      expect(captureRotation(exif: 6, width: 4000, height: 3000, meta: back).turns, 0);
      expect(captureRotation(exif: 6, width: 4000, height: 3000, meta: held(3)).turns, 3);
    });

    test('no tag, landscape pixels: sensor, then device (the list formula)', () {
      // Back camera, sensor 90: portrait → 90°, landscape left → 0°,
      // landscape right → 180°.
      expect(captureRotation(exif: 1, width: 4000, height: 3000, meta: held(0)).turns, 1);
      expect(captureRotation(exif: 0, width: 4000, height: 3000, meta: held(3)).turns, 0);
      expect(captureRotation(exif: 1, width: 4000, height: 3000, meta: held(1)).turns, 2);
      expect(captureRotation(exif: 1, width: 4000, height: 3000, meta: held(2)).turns, 3);
    });

    test('no tag, already portrait: the phone turned the pixels itself', () {
      expect(captureRotation(exif: 1, width: 3000, height: 4000, meta: held(0)).turns, 0);
      expect(captureRotation(exif: 1, width: 3000, height: 4000, meta: held(1)).turns, 1);
    });

    test('front camera turns the other way (sensor + device rotation)', () {
      // Sensor 270, portrait: 270°.
      expect(captureRotation(exif: 1, width: 4000, height: 3000, meta: held(0, front: true)).turns, 3);
      // Landscape left (device rotation 90°): 270 + 90 = 0°.
      expect(captureRotation(exif: 1, width: 4000, height: 3000, meta: held(3, front: true)).turns, 0);
      expect(captureRotation(exif: 1, width: 3000, height: 4000, meta: held(1, front: true)).turns, 3);
    });

    test('imports get the tag only', () {
      expect(captureRotation(exif: 1, width: 4000, height: 3000, meta: null), (turns: 0, mirror: false));
    });
  });

  group('classifyGravity', () {
    const g = 9.81;
    test('the four poses', () {
      expect(classifyGravity(0, g, 0), 0, reason: 'portrait');
      expect(classifyGravity(g, 0, 0), 3, reason: 'landscape left: top to the left');
      expect(classifyGravity(-g, 0, 0), 1, reason: 'landscape right');
      expect(classifyGravity(0, -g, 0), 2, reason: 'upside down');
    });

    test('flat over a page keeps the last confident pose', () {
      expect(classifyGravity(0.5, 1.2, 3), 3);
      expect(classifyGravity(0, 0, 1), 1);
    });

    test('hysteresis: needs to pass 60° from the current pose to switch', () {
      double x(double deg) => g * math.sin(deg * math.pi / 180);
      double y(double deg) => g * math.cos(deg * math.pi / 180);
      // From portrait, tipping left: 50° stays portrait, 65° switches.
      expect(classifyGravity(x(50), y(50), 0), 0);
      expect(classifyGravity(x(65), y(65), 0), 3);
      // And back from landscape left: 40° (50° from its centre) stays.
      expect(classifyGravity(x(40), y(40), 3), 3);
      expect(classifyGravity(x(25), y(25), 3), 0);
    });
  });
}
