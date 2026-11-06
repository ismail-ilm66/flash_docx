import 'dart:ui';

import 'package:flash_dox/features/photo/domain/photo_frame.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('photo sheet', () {
    test('35 × 45 mm: A4 holds 25 (5 × 5), 4 × 6 in holds 6 (2 × 3)', () {
      expect(PhotoSheetCalculator.capacity(35, 45, PhotoPaper.a4), (cols: 5, rows: 5));
      expect(PhotoSheetCalculator.full(35, 45, PhotoPaper.fourBySix), 6);
      expect(PhotoSheetCalculator.capacity(35, 45, PhotoPaper.fourBySix), (cols: 2, rows: 3));
    });

    test('counts: 4 · 8 · 12 · 16 · Full, only those that fit', () {
      expect(PhotoSheetCalculator.counts(35, 45, PhotoPaper.a4), [4, 8, 12, 16, 25]);
      expect(PhotoSheetCalculator.counts(35, 45, PhotoPaper.fourBySix), [4, 6]);
      expect(PhotoSheetCalculator.counts(50.8, 50.8, PhotoPaper.a4), [4, 8, 12, 15]);
    });

    test('a full sheet is centred, inside the margins, with 4 mm gaps', () {
      final items = PhotoSheetCalculator.layout(const PrintItemSpec(widthMm: 35, heightMm: 45, count: 25));
      expect(items, hasLength(25));
      expect(items.first.x, closeTo((210 - (5 * 35 + 4 * 4)) / 2, 1e-9));
      expect(items[1].x - items[0].x, closeTo(39, 1e-9));
      expect(items[5].y - items[0].y, closeTo(49, 1e-9));
      for (final it in items) {
        expect(it.x, greaterThanOrEqualTo(5));
        expect(it.y, greaterThanOrEqualTo(5));
        expect(it.x + it.w, lessThanOrEqualTo(205));
        expect(it.y + it.h, lessThanOrEqualTo(292));
      }
    });

    test('a partial sheet fills rows from the top on the full grid', () {
      final items = PhotoSheetCalculator.layout(const PrintItemSpec(widthMm: 35, heightMm: 45, count: 8));
      expect(items, hasLength(8));
      expect(items.first.y, 5, reason: 'top margin');
      expect(items.where((i) => i.y == items.first.y), hasLength(5), reason: 'first row full');
      final full = PhotoSheetCalculator.layout(const PrintItemSpec(widthMm: 35, heightMm: 45, count: 25));
      expect(items.first.x, full.first.x, reason: 'same columns as a full sheet');
    });

    test('ID card layouts are untouched', () {
      expect(PrintLayoutCalculator.allowedCopies(PrintKind.idCard, PrintOutput.pdfDoubleSided), [1, 2, 4, 6, 8]);
    });
  });

  group('crop frame', () {
    const image = Size(3000, 4000);
    const frame = Rect.fromLTWH(50, 100, 280, 360); // 35:45

    test('cover fills the frame and crops the centre at the frame aspect', () {
      final p = PhotoPlacement.cover(image, frame);
      final q = p.cropFor(image, frame);
      expect((q.tr.x - q.tl.x) * image.width / ((q.bl.y - q.tl.y) * image.height), closeTo(35 / 45, 1e-6));
      expect(q.tl.x, closeTo(0, 1e-6), reason: 'a 3:4 photo is narrower than 35:45: full width');
      expect((q.tl.y + q.bl.y) / 2, closeTo(0.5, 1e-6));
    });

    test('zooming about the frame centre keeps it centred; clamp never shows a gap', () {
      final cover = PhotoPlacement.cover(image, frame);
      final before = cover.cropFor(image, frame);
      final p = cover.transformed(factor: 2, focal: frame.center);
      final q = p.cropFor(image, frame);
      expect((q.tl.x + q.tr.x) / 2, closeTo(0.5, 1e-6));
      expect(q.br.y - q.tl.y, closeTo((before.br.y - before.tl.y) / 2, 1e-6), reason: 'half the height at 2×');

      final dragged = p.transformed(factor: 1, focal: Offset.zero, pan: const Offset(5000, 5000)).clamp(image, frame);
      final dq = dragged.cropFor(image, frame);
      expect(dq.tl.x, closeTo(0, 1e-9));
      expect(dq.tl.y, closeTo(0, 1e-9));

      final tiny = PhotoPlacement.cover(image, frame).transformed(factor: 0.2, focal: frame.center).clamp(image, frame);
      expect(tiny.scale, closeTo(PhotoPlacement.cover(image, frame).scale, 1e-9));
    });

    test('fromCrop puts a saved crop back exactly', () {
      final p = PhotoPlacement.cover(image, frame).transformed(factor: 1.7, focal: const Offset(120, 200));
      final q = p.clamp(image, frame).cropFor(image, frame);
      final back = PhotoPlacement.fromCrop(q, image, frame).cropFor(image, frame);
      expect(back.tl.x, closeTo(q.tl.x, 1e-9));
      expect(back.br.y, closeTo(q.br.y, 1e-9));
    });
  });
}
