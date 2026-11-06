import 'dart:ui';

import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1-2 / P1-4: screen ↔ photo through the full-screen cover crop.
void main() {
  const photo = 3 / 4; // 4:3 sensor, portrait

  group('cover crop', () {
    test('19.5:9 phone (390 × 845): the photo sides run off the screen', () {
      const v = Size(390, 845);
      // k = max(390 / 0.75, 845) = 845 → photo shown 633.75 wide.
      final left = PreviewGeometry.viewportToPhoto(const Offset(0, 0.5), photoAspect: photo, viewport: v);
      expect(left.dx, closeTo(121.875 / 633.75, 1e-6));
      expect(left.dy, closeTo(0.5, 1e-9));
      final centre = PreviewGeometry.viewportToPhoto(const Offset(0.5, 0.5), photoAspect: photo, viewport: v);
      expect(centre, const Offset(0.5, 0.5));
      final top = PreviewGeometry.viewportToPhoto(const Offset(0.5, 0), photoAspect: photo, viewport: v);
      expect(top.dy, closeTo(0, 1e-9), reason: 'full height is visible');
    });

    test('16:9 phone (360 × 640)', () {
      const v = Size(360, 640);
      // k = max(480, 640) = 640 → shown 480 wide, 60 px off each side.
      final left = PreviewGeometry.viewportToPhoto(const Offset(0, 0.25), photoAspect: photo, viewport: v);
      expect(left.dx, closeTo(60 / 480, 1e-9));
      expect(left.dy, closeTo(0.25, 1e-9));
    });

    test('a 3:4 screen shows the whole photo', () {
      const v = Size(300, 400);
      expect(PreviewGeometry.viewportToPhoto(Offset.zero, photoAspect: photo, viewport: v), Offset.zero);
      expect(PreviewGeometry.viewportToPhoto(const Offset(1, 1), photoAspect: photo, viewport: v), const Offset(1, 1));
    });
  });

  group('guide frame (P1-4)', () {
    const v = Size(390, 845);
    const area = Rect.fromLTWH(0, 110 / 845, 1, (845 - 110 - 284) / 845);

    test('ID frame is landscape, a constant on screen, centred in the visible area', () {
      final r = PreviewGeometry.guideRect(85.6 / 54, viewport: v, area: area);
      expect(r.width * v.width / (r.height * v.height), closeTo(85.6 / 54, 1e-9));
      expect(r.width * v.width, closeTo(0.84 * 390, 1e-9));
      expect(r.center.dy, closeTo(area.center.dy, 1e-9));
      // Same inputs → same frame, whatever happened before.
      expect(PreviewGeometry.guideRect(85.6 / 54, viewport: v, area: area), r);
    });

    test('the photo-space guide is narrower than on screen on a tall phone', () {
      final q = PreviewGeometry.guideQuad(85.6 / 54, photoAspect: photo, viewport: v, area: area);
      final r = PreviewGeometry.guideRect(85.6 / 54, viewport: v, area: area);
      // 84 % of the screen width is 0.84 × 390 / 633.75 ≈ 52 % of the photo.
      expect(q.tr.x - q.tl.x, closeTo(r.width * 390 / 633.75, 1e-6));
      expect(q.tl.y, closeTo(r.top, 1e-6), reason: 'vertical axis is not cropped');
    });
  });
}
