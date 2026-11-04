import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quad', () {
    test('full covers the unit square', () {
      final q = Quad.full();
      expect(q.area, closeTo(1, 1e-9));
      expect(q.isConvex, isTrue);
    });

    test('fromUnordered sorts corners TL, TR, BR, BL', () {
      final q = Quad.fromUnordered(const [
        Pt(0.9, 0.8), // BR
        Pt(0.1, 0.1), // TL
        Pt(0.1, 0.9), // BL
        Pt(0.9, 0.2), // TR
      ]);
      expect(q.tl, const Pt(0.1, 0.1));
      expect(q.tr, const Pt(0.9, 0.2));
      expect(q.br, const Pt(0.9, 0.8));
      expect(q.bl, const Pt(0.1, 0.9));
    });

    test('isConvex rejects a bow-tie', () {
      const q = Quad(tl: Pt(0, 0), tr: Pt(1, 1), br: Pt(1, 0), bl: Pt(0, 1));
      expect(q.isConvex, isFalse);
    });

    test('withPoint replaces one corner', () {
      final q = Quad.full().withPoint(2, const Pt(0.5, 0.5));
      expect(q.br, const Pt(0.5, 0.5));
      expect(q.tl, const Pt(0, 0));
    });

    test('bent and crossed shapes are not convex', () {
      // Dragging BR past TL folds the shape.
      final bent = Quad.full().withPoint(2, const Pt(0.1, 0.1));
      expect(bent.isConvex, isFalse);
      // Crossing: swap TR and BR.
      const crossed = Quad(tl: Pt(0, 0), tr: Pt(1, 1), br: Pt(1, 0), bl: Pt(0, 1));
      expect(crossed.isConvex, isFalse);
      // A normal drag stays convex.
      expect(Quad.full().withPoint(2, const Pt(0.8, 0.9)).isConvex, isTrue);
    });

    test('json round-trip', () {
      final q = Quad.full(inset: 0.05);
      expect(Quad.fromJson(q.toJson()), q);
    });
  });

  group('PageEdits', () {
    test('rotate wraps around', () {
      var e = const PageEdits();
      for (var i = 0; i < 5; i++) {
        e = e.rotateRight();
      }
      expect(e.normalizedTurns, 1);
      expect(e.rotateLeft().rotateLeft().normalizedTurns, 3);
    });

    test('applyLook copies filter and sliders but keeps crop', () {
      final crop = Quad.full(inset: 0.1);
      final target = PageEdits(crop: crop, quarterTurns: 1);
      const source = PageEdits(
        filter: FilterType.bwPrint,
        brightness: 20,
        contrast: -10,
      );
      final out = target.applyLook(source);
      expect(out.filter, FilterType.bwPrint);
      expect(out.brightness, 20);
      expect(out.contrast, -10);
      expect(out.crop, crop);
      expect(out.quarterTurns, 1);
    });

    test('ScanPage.withEdits clears caches', () {
      const page = ScanPage(
        id: 'p',
        documentId: 'd',
        originalPath: '/o.jpg',
        edits: PageEdits(),
        order: 0,
        processedPath: '/p.jpg',
        thumbPath: '/t.jpg',
        ocrText: 'hello',
      );
      final out = page.withEdits(const PageEdits(filter: FilterType.grayscale));
      expect(out.processedPath, isNull);
      expect(out.thumbPath, isNull);
      expect(out.ocrText, isNull);
      expect(out.edits.filter, FilterType.grayscale);
    });
  });
}
