import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a4W = PrintLayoutCalculator.sheetW;
  const a4H = PrintLayoutCalculator.sheetH;

  PrintLayoutSpec spec(PrintKind k, PrintOutput o, int copies, {bool back = true}) =>
      PrintLayoutSpec(
        kind: k,
        output: o,
        copies: copies,
        frontPath: 'f',
        backPath: back ? 'b' : null,
      );

  bool inside(PlacedItem it) =>
      it.x >= 0 && it.y >= 0 && it.x + it.w <= a4W + 1e-9 && it.y + it.h <= a4H + 1e-9;

  group('grids', () {
    test('ID card copies map to the documented grid', () {
      expect(PrintLayoutCalculator.grid(PrintKind.idCard, 1), (cols: 1, rows: 1, rotated: false));
      expect(PrintLayoutCalculator.grid(PrintKind.idCard, 2), (cols: 1, rows: 2, rotated: false));
      expect(PrintLayoutCalculator.grid(PrintKind.idCard, 4), (cols: 2, rows: 2, rotated: false));
      expect(PrintLayoutCalculator.grid(PrintKind.idCard, 6), (cols: 2, rows: 3, rotated: false));
      expect(PrintLayoutCalculator.grid(PrintKind.idCard, 8), (cols: 2, rows: 4, rotated: false));
    });

    test('passport × 4 is rotated', () {
      expect(PrintLayoutCalculator.grid(PrintKind.passport, 4), (cols: 2, rows: 2, rotated: true));
      expect(PrintLayoutCalculator.allowedCopies(PrintKind.passport, PrintOutput.pdfDoubleSided), [1, 2, 4]);
      expect(PrintLayoutCalculator.allowedCopies(PrintKind.idCard, PrintOutput.image), [1]);
    });

    test('every layout stays inside A4 at real size', () {
      for (final kind in PrintKind.values) {
        for (final output in PrintOutput.values) {
          for (final n in PrintLayoutCalculator.allowedCopies(kind, output)) {
            final layout = PrintLayoutCalculator.layout(spec(kind, output, n, back: kind == PrintKind.idCard));
            for (final page in layout.pages) {
              for (final it in page) {
                expect(inside(it), isTrue, reason: '$kind $output ×$n: $it');
              }
            }
          }
        }
      }
    });
  });

  group('double-sided', () {
    test('produces two pages with the same count of items', () {
      final layout = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.pdfDoubleSided, 4));
      expect(layout.pages.length, 2);
      expect(layout.pages[0].length, 4);
      expect(layout.pages[1].length, 4);
      expect(layout.pages[0].every((i) => !i.isBack), isTrue);
      expect(layout.pages[1].every((i) => i.isBack), isTrue);
    });

    test('backs are mirrored left-to-right on the same rows', () {
      final layout = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.pdfDoubleSided, 4));
      final fronts = layout.pages[0];
      final backs = layout.pages[1];
      for (var i = 0; i < fronts.length; i++) {
        expect(backs[i].y, closeTo(fronts[i].y, 1e-9));
        expect(backs[i].x, closeTo(a4W - fronts[i].x - fronts[i].w, 1e-9));
      }
    });

    test('a single card is centred', () {
      final it = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.pdfDoubleSided, 1)).pages[0].single;
      expect(it.x, closeTo((a4W - 85.6) / 2, 1e-9));
      expect(it.y, closeTo((a4H - 54) / 2, 1e-9));
      expect(it.w, 85.6);
      expect(it.h, 54);
    });

    test('no back → single page', () {
      final layout = PrintLayoutCalculator.layout(spec(PrintKind.passport, PrintOutput.pdfDoubleSided, 2, back: false));
      expect(layout.pages.length, 1);
    });
  });

  group('one page', () {
    test('front and back sit side by side per copy', () {
      final items = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.pdfOnePage, 2)).pages.single;
      expect(items.length, 4);
      expect(items[0].isBack, isFalse);
      expect(items[1].isBack, isTrue);
      expect(items[1].x, closeTo(items[0].x + items[0].w + PrintLayoutCalculator.gap, 1e-9));
      expect(items[1].y, items[0].y);
      expect(items[2].y, closeTo(items[0].y + items[0].h + PrintLayoutCalculator.gap, 1e-9));
    });

    test('one-page allows at most 4 copies for ID card', () {
      expect(PrintLayoutCalculator.allowedCopies(PrintKind.idCard, PrintOutput.pdfOnePage), [1, 2, 4]);
    });
  });

  group('image', () {
    test('is one front above one back, whatever copies says', () {
      final items = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.image, 8)).pages.single;
      expect(items.length, 2);
      expect(items[0].isBack, isFalse);
      expect(items[1].isBack, isTrue);
      expect(items[1].y, greaterThan(items[0].y + items[0].h));
      expect(items[1].x, items[0].x);
      expect(items[0].w, 85.6);
      expect(items[0].h, 54);
    });

    test('content box wraps the cards with a 6 mm margin', () {
      final items = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.image, 1)).pages.single;
      final box = PrintLayoutCalculator.contentBox(items);
      expect(box.w, closeTo(85.6 + 12, 1e-9));
      expect(box.h, closeTo(54 * 2 + PrintLayoutCalculator.gap * 2 + 12, 1e-9));
      expect(box.x, closeTo(items[0].x - 6, 1e-9));
    });
  });

  group('crop marks', () {
    test('eight marks per card, all outside the card and inside the sheet', () {
      final items = PrintLayoutCalculator.layout(spec(PrintKind.idCard, PrintOutput.pdfDoubleSided, 8)).pages.first;
      final marks = PrintLayoutCalculator.cropMarks(items);
      expect(marks.length, items.length * 8);
      for (final it in items) {
        for (final ((x1, y1), (x2, y2)) in marks) {
          final insideCard = x1 > it.x && x1 < it.x + it.w && y1 > it.y && y1 < it.y + it.h;
          expect(insideCard, isFalse, reason: 'mark ($x1,$y1)-($x2,$y2) overlaps $it');
        }
      }
      for (final ((x1, y1), (x2, y2)) in marks) {
        for (final v in [x1, x2]) {
          expect(v, inInclusiveRange(0, a4W));
        }
        for (final v in [y1, y2]) {
          expect(v, inInclusiveRange(0, a4H));
        }
      }
    });
  });
}
