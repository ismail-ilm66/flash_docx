import 'dart:math' as math;

/// What the camera knew at the shutter (round 5, P0-1), so the photo can be
/// turned upright even when the phone writes no EXIF orientation tag.
class CaptureMeta {
  const CaptureMeta({required this.sensorOrientation, required this.deviceTurns, this.frontCamera = false});

  /// `CameraDescription.sensorOrientation`: 90 on most back cameras, 270 on
  /// most front ones.
  final int sensorOrientation;

  /// How the phone was held, from the accelerometer (not the UI, which is
  /// locked to portrait): clockwise quarter turns that bring a portrait
  /// capture upright. Portrait 0, landscape right 1, upside down 2,
  /// landscape left 3.
  final int deviceTurns;
  final bool frontCamera;

  @override
  String toString() => 'sensor=$sensorOrientation device=$deviceTurns${frontCamera ? ' front' : ''}';
}

/// Whether front-camera files come out mirrored on disk and need flipping.
/// CameraX and AVFoundation save them as the sensor sees them (not
/// mirrored); confirm with a page of text on the test phones.
const frontCaptureMirrored = false;

/// The extra rotation a capture needs after its EXIF tag (P0-1):
///
/// | EXIF tag      | Pixels    | Clockwise turns              |
/// |---------------|-----------|------------------------------|
/// | 2–8           | any       | device                       |
/// | missing or 1  | landscape | sensor, then device          |
/// | missing or 1  | portrait  | device                       |
///
/// "Landscape pixels with no tag" is a phone that saved the sensor's pixels
/// and didn't say so; a phone that already turned them saves portrait. The
/// front camera turns the other way. Imports ([meta] null) get the tag only.
({int turns, bool mirror}) captureRotation({required int exif, required int width, required int height, CaptureMeta? meta}) {
  if (meta == null) return (turns: 0, mirror: false);
  final device = meta.frontCamera ? -meta.deviceTurns : meta.deviceTurns;
  final untagged = exif <= 1;
  final sensor = untagged && width > height ? meta.sensorOrientation ~/ 90 : 0;
  return (turns: ((sensor + device) % 4 + 4) % 4, mirror: meta.frontCamera && frontCaptureMirrored);
}

/// Classifies one accelerometer reading (m/s², Android axes: x to the
/// phone's right, y to its top; both platforms report it this way) into
/// device turns. Flat (little gravity in the screen plane) keeps
/// [previous], and a pose must be [hysteresis] degrees past the 45° line to
/// switch, so it doesn't flicker.
int classifyGravity(double x, double y, int previous, {double flat = 3, double hysteresis = 15}) {
  if (x * x + y * y < flat * flat) return previous;
  // atan2(x, y): 0° upright, +90° top tipped left (x up), ±180° upside down.
  final angle = math.atan2(x, y) * 180 / math.pi;
  int turnsFor(double a) => ((-(a / 90).round()) % 4 + 4) % 4;
  final candidate = turnsFor(angle);
  if (candidate == previous) return previous;
  // Centre of the previous pose, in the same angle frame.
  final centre = -previous * 90.0;
  var diff = (angle - centre) % 360;
  if (diff > 180) diff -= 360;
  return diff.abs() > 45 + hysteresis ? candidate : previous;
}
