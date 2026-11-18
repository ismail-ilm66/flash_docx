
import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 7, P0-2: the preview shows the whole photo, never a cover crop.
void main() {
  const portrait169 = 9 / 16;

  test('the box has the photo aspect and leaves room for the shutter row', () {
    for (final (screen, pad) in [
      (const Size(360, 780), const EdgeInsets.only(top: 24, bottom: 48)), // Y9 Prime, nav buttons
      (const Size(390, 844), const EdgeInsets.only(top: 47, bottom: 34)), // iPhone 13
      (const Size(412, 915), const EdgeInsets.only(top: 24, bottom: 16)), // gesture nav
      (const Size(800, 1280), const EdgeInsets.only(top: 24, bottom: 48)), // tablet
    ]) {
      final l = CameraLayout.of(screen, pad, portrait169, modes: true);
      expect(l.box.width / l.box.height, closeTo(portrait169, 1e-9), reason: '$screen');
      expect(l.box.top, pad.top);
      expect(l.box.left, greaterThanOrEqualTo(0));
      expect(l.box.right, lessThanOrEqualTo(screen.width + 1e-9));
      expect(screen.height - pad.bottom - l.box.bottom, greaterThanOrEqualTo(CameraLayout.controlsHeight - 1e-9), reason: '$screen');
      expect((l.box.left + l.box.right) / 2, closeTo(screen.width / 2, 1e-9));
    }
  });

  test('full width when it fits', () {
    final l = CameraLayout.of(const Size(800, 1280), EdgeInsets.zero, 3 / 4, modes: true);
    expect(l.box.width, 800);
  });

  test('a point in the box is the same point in the photo', () {
    final l = CameraLayout.of(const Size(360, 780), const EdgeInsets.only(top: 24, bottom: 48), portrait169, modes: true);
    for (final p in [Offset.zero, const Offset(1, 1), const Offset(0.3, 0.8)]) {
      final m = PreviewGeometry.viewportToPhoto(p, photoAspect: portrait169, viewport: l.box.size);
      expect(m.dx, closeTo(p.dx, 1e-9));
      expect(m.dy, closeTo(p.dy, 1e-9));
    }
  });

  test('the card frame sits between the top bar and the pills', () {
    final l = CameraLayout.of(const Size(360, 780), const EdgeInsets.only(top: 24, bottom: 48), portrait169, modes: true);
    final r = PreviewGeometry.guideRect(1.585, viewport: l.box.size, area: l.guideArea);
    expect(r.top * l.box.height, greaterThanOrEqualTo(CameraLayout.topBar));
    expect((1 - r.bottom) * l.box.height, greaterThanOrEqualTo(CameraLayout.bottomOverlay(modes: true)));
  });
}
