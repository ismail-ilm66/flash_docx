import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/domain/crop_geometry.dart';
import 'package:flash_dox/features/editor/domain/snap_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const square = [Offset(100, 100), Offset(300, 100), Offset(300, 300), Offset(100, 300)];
  // A trapezoid: left and right edges lean inwards towards the top.
  const trap = [Offset(140, 100), Offset(260, 100), Offset(300, 300), Offset(100, 300)];

  void expectOffset(Offset a, Offset b) {
    expect(a.dx, closeTo(b.dx, 1e-6));
    expect(a.dy, closeTo(b.dy, 1e-6));
  }

  group('mid-edge handles (P1-2)', () {
    test('top edge moves parallel; only the normal component counts', () {
      final q = CropGeometry.moveEdge(square, 0, const Offset(37, 20));
      expectOffset(q[0], const Offset(100, 120));
      expectOffset(q[1], const Offset(300, 120));
      expectOffset(q[2], square[2]);
      expectOffset(q[3], square[3]);
    });

    test('corners slide along the neighbouring edges of a trapezoid', () {
      final q = CropGeometry.moveEdge(trap, 0, const Offset(0, 100));
      // Left edge (100,300)→(140,100) at y = 200 is x = 120; right edge at 280.
      expectOffset(q[0], const Offset(120, 200));
      expectOffset(q[1], const Offset(280, 200));
      expect(CropGeometry.isConvex(q), isTrue);
    });

    test('nearly parallel neighbour: the corner is translated along the normal', () {
      // Right edge almost parallel to the top edge (degenerate quad).
      const q0 = [Offset.zero, Offset(100, 0), Offset(200, 2), Offset(0, 100)];
      final q = CropGeometry.moveEdge(q0, 0, const Offset(0, 10));
      expectOffset(q[1], const Offset(100, 10));
    });

    test('a move that crosses the opposite edge is not convex (caller rejects it)', () {
      final q = CropGeometry.moveEdge(square, 0, const Offset(0, 260));
      expect(CropGeometry.isConvex(q), isFalse);
    });
  });

  group('magnetic edges (P1-3)', () {
    Offset toScreen(Pt p) => Offset(p.x * 400, p.y * 400);
    // A line along y = 200 (x 50..350) and a corner at (300, 100).
    const candidates = SnapCandidates(
      lines: [(Pt(50 / 400, 0.5), Pt(350 / 400, 0.5))],
      corners: [Pt(0.75, 0.25)],
    );

    test('a corner snaps to a candidate corner within 16 dp and holds until 24 dp', () {
      final s = Snapper(candidates, toScreen);
      final r1 = s.corner(const Offset(310, 110)); // 14.1 dp away
      expect(r1.snapped, isTrue);
      expect(r1.justSnapped, isTrue);
      expectOffset(r1.value, const Offset(300, 100));
      final r2 = s.corner(const Offset(318, 112)); // 21.6 dp: still held
      expect(r2.justSnapped, isFalse);
      expectOffset(r2.value, const Offset(300, 100));
      final r3 = s.corner(const Offset(330, 100)); // 30 dp: broken
      expect(r3.snapped, isFalse);
      expectOffset(r3.value, const Offset(330, 100));
    });

    test('otherwise a corner snaps onto the nearest line within 10 dp', () {
      final s = Snapper(candidates, toScreen);
      final r = s.corner(const Offset(120, 208));
      expect(r.snapped, isTrue);
      expectOffset(r.value, const Offset(120, 200));
      expect(s.corner(const Offset(120, 240)).snapped, isFalse, reason: '40 dp is past the break-away');
      s.reset();
      expect(s.corner(const Offset(120, 215)).snapped, isFalse, reason: '15 dp > 10 dp');
    });

    test('an edge snaps to a parallel line within 12 dp, not to one at 8°+', () {
      final s = Snapper(candidates, toScreen);
      // Bottom edge of a quad near y = 200.
      const q = [Offset(100, 50), Offset(300, 50), Offset(300, 191), Offset(100, 191)];
      final r = s.edge(q, 2);
      expect(r.snapped, isTrue);
      expect(r.value[2].dy, closeTo(200, 1e-6));
      expect(r.value[3].dy, closeTo(200, 1e-6));

      final s2 = Snapper(candidates, toScreen);
      // Tilted ~11°: close but not parallel.
      const tilted = [Offset(100, 50), Offset(300, 50), Offset(300, 210), Offset(100, 171)];
      expect(s2.edge(tilted, 2).snapped, isFalse);
    });
  });
}
