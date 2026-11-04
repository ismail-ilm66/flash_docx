import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';

/// One placed card on an A4 sheet. All values in millimetres.
class PlacedItem {
  const PlacedItem({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotated = false,
    this.isBack = false,
  });

  final double x;
  final double y;

  /// Placed width / height (already swapped when [rotated]).
  final double w;
  final double h;

  /// Image is rotated 90° to fit (passport × 4).
  final bool rotated;
  final bool isBack;

  @override
  String toString() => 'PlacedItem($x, $y, $w×$h${rotated ? ' r' : ''}${isBack ? ' back' : ''})';
}

class SheetLayout {
  const SheetLayout(this.pages);

  /// One list of items per PDF page.
  final List<List<PlacedItem>> pages;
}

/// Pure maths for §8 of the plan. Unit-tested, no Flutter imports.
abstract final class PrintLayoutCalculator {
  static const double sheetW = PaperMm.a4Width;
  static const double sheetH = PaperMm.a4Height;
  static const double gap = 6;

  static ({double w, double h}) cardSize(PrintKind k) => switch (k) {
        PrintKind.idCard => (w: CardMm.id1Width, h: CardMm.id1Height),
        PrintKind.passport => (w: CardMm.id3Width, h: CardMm.id3Height),
      };

  /// Copies offered per kind and output.
  static List<int> allowedCopies(PrintKind kind, PrintOutput output) {
    if (kind == PrintKind.passport) return const [1, 2, 4];
    if (output == PrintOutput.pdfOnePage) return const [1, 2, 4];
    return const [1, 2, 4, 6, 8];
  }

  /// Grid (cols × rows) and whether the card is rotated for [copies].
  static ({int cols, int rows, bool rotated}) grid(PrintKind kind, int copies) {
    if (kind == PrintKind.passport) {
      return switch (copies) {
        1 => (cols: 1, rows: 1, rotated: false),
        2 => (cols: 1, rows: 2, rotated: false),
        _ => (cols: 2, rows: 2, rotated: true),
      };
    }
    return switch (copies) {
      1 => (cols: 1, rows: 1, rotated: false),
      2 => (cols: 1, rows: 2, rotated: false),
      4 => (cols: 2, rows: 2, rotated: false),
      6 => (cols: 2, rows: 3, rotated: false),
      _ => (cols: 2, rows: 4, rotated: false),
    };
  }

  /// Centred grid of [copies] items of one side.
  static List<PlacedItem> _gridItems(
    PrintKind kind,
    int copies, {
    required bool isBack,
    bool mirror = false,
  }) {
    final g = grid(kind, copies);
    final c = cardSize(kind);
    final w = g.rotated ? c.h : c.w;
    final h = g.rotated ? c.w : c.h;
    final groupW = g.cols * w + (g.cols - 1) * gap;
    final groupH = g.rows * h + (g.rows - 1) * gap;
    final originX = (sheetW - groupW) / 2;
    final originY = (sheetH - groupH) / 2;
    final items = <PlacedItem>[];
    for (var r = 0; r < g.rows; r++) {
      for (var col = 0; col < g.cols; col++) {
        if (items.length >= copies) break;
        var x = originX + col * (w + gap);
        final y = originY + r * (h + gap);
        if (mirror) x = sheetW - x - w;
        items.add(PlacedItem(x: x, y: y, w: w, h: h, rotated: g.rotated, isBack: isBack));
      }
    }
    return items;
  }

  /// Front and back side by side, one pair per row, centred.
  static List<PlacedItem> _pairItems(PrintKind kind, int copies) {
    final c = cardSize(kind);
    final pairW = c.w * 2 + gap;
    final groupH = copies * c.h + (copies - 1) * gap;
    final originX = (sheetW - pairW) / 2;
    final originY = (sheetH - groupH) / 2;
    return [
      for (var i = 0; i < copies; i++) ...[
        PlacedItem(x: originX, y: originY + i * (c.h + gap), w: c.w, h: c.h),
        PlacedItem(x: originX + c.w + gap, y: originY + i * (c.h + gap), w: c.w, h: c.h, isBack: true),
      ],
    ];
  }

  static SheetLayout layout(PrintLayoutSpec spec) {
    final kind = spec.kind;
    final copies = spec.copies;
    switch (spec.output) {
      case PrintOutput.image:
        // Fronts, then backs below them (same grid, stacked). When both sides
        // exist we place the two grids in the top and bottom halves.
        if (!spec.hasBack) return SheetLayout([_gridItems(kind, copies, isBack: false)]);
        return SheetLayout([_stackedFrontBack(kind, copies)]);
      case PrintOutput.pdfDoubleSided:
        final fronts = _gridItems(kind, copies, isBack: false);
        if (!spec.hasBack) return SheetLayout([fronts]);
        // Backs mirrored left-to-right so each lands behind its front after a
        // long-edge flip. Rows stay the same.
        final backs = _gridItems(kind, copies, isBack: true, mirror: true);
        return SheetLayout([fronts, backs]);
      case PrintOutput.pdfOnePage:
        if (!spec.hasBack) return SheetLayout([_gridItems(kind, copies, isBack: false)]);
        return SheetLayout([_pairItems(kind, copies)]);
    }
  }

  /// Front grid in the top half, back grid in the bottom half.
  static List<PlacedItem> _stackedFrontBack(PrintKind kind, int copies) {
    final g = grid(kind, copies);
    final c = cardSize(kind);
    final w = g.rotated ? c.h : c.w;
    final h = g.rotated ? c.w : c.h;
    // Use the layout of `copies` per side, but limit rows so both halves fit.
    final groupW = g.cols * w + (g.cols - 1) * gap;
    final groupH = g.rows * h + (g.rows - 1) * gap;
    final totalH = groupH * 2 + gap * 2;
    final originX = (sheetW - groupW) / 2;
    final originY = (sheetH - totalH) / 2;
    final items = <PlacedItem>[];
    for (final (side, isBack) in [(0, false), (1, true)]) {
      var n = 0;
      for (var r = 0; r < g.rows; r++) {
        for (var col = 0; col < g.cols; col++) {
          if (n++ >= copies) break;
          items.add(
            PlacedItem(
              x: originX + col * (w + gap),
              y: originY + side * (groupH + gap * 2) + r * (h + gap),
              w: w,
              h: h,
              rotated: g.rotated,
              isBack: isBack,
            ),
          );
        }
      }
    }
    return items;
  }

  /// Does a stacked image layout fit the sheet? (ID card × 8 does not.)
  static bool fitsStacked(PrintKind kind, int copies) {
    final g = grid(kind, copies);
    final c = cardSize(kind);
    final h = g.rotated ? c.w : c.h;
    final groupH = g.rows * h + (g.rows - 1) * gap;
    return groupH * 2 + gap * 2 <= sheetH;
  }
}
