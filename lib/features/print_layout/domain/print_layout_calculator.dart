import 'dart:math' as math;

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
  String toString() =>
      'PlacedItem($x, $y, $w×$h${rotated ? ' r' : ''}${isBack ? ' back' : ''})';
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

  /// The Image output's border and front-to-back gap (P1-6).
  static const double imageBorder = 4;
  static const double imageGap = 4;

  /// The page the layout is drawn on: A4 for the PDFs, the tight image
  /// (card 93.6 × 120 mm, passport 133 × 96 mm) for the Image output.
  static ({double w, double h}) pageSize(PrintLayoutSpec spec) {
    if (spec.output != PrintOutput.image) return (w: sheetW, h: sheetH);
    final c = cardSize(spec.kind);
    final sides = spec.hasBack ? 2 : 1;
    return (
      w: c.w + 2 * imageBorder,
      h: sides * c.h + (sides - 1) * imageGap + 2 * imageBorder,
    );
  }

  static ({double w, double h}) cardSize(PrintKind k) => switch (k) {
    PrintKind.idCard => (w: CardMm.id1Width, h: CardMm.id1Height),
    PrintKind.passport => (w: CardMm.id3Width, h: CardMm.id3Height),
  };

  /// Copies offered per kind and output. The image output is always one
  /// front-above-back image, so it has no copies choice.
  static List<int> allowedCopies(PrintKind kind, PrintOutput output) {
    if (output == PrintOutput.image) return const [1];
    if (kind == PrintKind.passport) return const [1, 2, 4];
    // One-page pairs only fit up to 4.
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
        items.add(
          PlacedItem(
            x: x,
            y: y,
            w: w,
            h: h,
            rotated: g.rotated,
            isBack: isBack,
          ),
        );
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
        PlacedItem(
          x: originX + c.w + gap,
          y: originY + i * (c.h + gap),
          w: c.w,
          h: c.h,
          isBack: true,
        ),
      ],
    ];
  }

  static SheetLayout layout(PrintLayoutSpec spec) {
    final kind = spec.kind;
    final copies = spec.copies;
    switch (spec.output) {
      case PrintOutput.image:
        // A tight image for WhatsApp / email (round 5, P1-6): front above
        // back (or the front alone) with a 4 mm gap and a 4 mm white
        // border; no A4 page. See [pageSize].
        final c = cardSize(kind);
        return SheetLayout([
          [
            PlacedItem(x: imageBorder, y: imageBorder, w: c.w, h: c.h),
            if (spec.hasBack)
              PlacedItem(
                x: imageBorder,
                y: imageBorder + c.h + imageGap,
                w: c.w,
                h: c.h,
                isBack: true,
              ),
          ],
        ]);
      case PrintOutput.pdfDoubleSided:
        final fronts = _gridItems(kind, copies, isBack: false);
        if (!spec.hasBack) return SheetLayout([fronts]);
        // Backs mirrored left-to-right so each lands behind its front after a
        // long-edge flip. Rows stay the same.
        final backs = _gridItems(kind, copies, isBack: true, mirror: true);
        return SheetLayout([fronts, backs]);
      case PrintOutput.pdfOnePage:
        if (!spec.hasBack) {
          return SheetLayout([_gridItems(kind, copies, isBack: false)]);
        }
        return SheetLayout([_pairItems(kind, copies)]);
    }
  }

  /// Crop marks: for each item, four L-shaped corner marks drawn just
  /// outside the item (in the gap), [len] mm long, [offset] mm away from the
  /// edge so they never overlap the card. Each mark is a (from, to) segment.
  static List<((double, double), (double, double))> cropMarks(
    List<PlacedItem> items, {
    double len = 2.5,
    double offset = 0.5,
  }) {
    final marks = <((double, double), (double, double))>[];
    for (final it in items) {
      final l = it.x;
      final r = it.x + it.w;
      final t = it.y;
      final b = it.y + it.h;
      // Horizontal ticks beyond left/right edges, at top and bottom lines.
      for (final y in [t, b]) {
        marks.add(((l - offset - len, y), (l - offset, y)));
        marks.add(((r + offset, y), (r + offset + len, y)));
      }
      // Vertical ticks beyond top/bottom edges, at left and right lines.
      for (final x in [l, r]) {
        marks.add(((x, t - offset - len), (x, t - offset)));
        marks.add(((x, b + offset), (x, b + offset + len)));
      }
    }
    return marks;
  }
}

/// Photo paper for passport photos (feature 5).
enum PhotoPaper {
  a4(PaperMm.a4Width, PaperMm.a4Height, 5),
  // Photo paper prints nearly to the edge: 3 mm fits the usual 2 × 3.
  fourBySix(PaperMm.photo4x6Width, PaperMm.photo4x6Height, 3)
  ;

  const PhotoPaper(this.widthMm, this.heightMm, this.marginMm);
  final double widthMm;
  final double heightMm;
  final double marginMm;
}

/// One kind of item repeated on a sheet (feature 5's generalisation of the
/// card grid): its size, how many, the paper, the gap and whether dashed cut
/// lines are drawn. ID cards keep their own layouts above.
class PrintItemSpec {
  const PrintItemSpec({
    required this.widthMm,
    required this.heightMm,
    required this.count,
    this.paper = PhotoPaper.a4,
    this.gapMm = 4,
    this.cutLines = true,
  });

  final double widthMm;
  final double heightMm;
  final int count;
  final PhotoPaper paper;
  final double gapMm;
  final bool cutLines;

  double get marginMm => paper.marginMm;
}

abstract final class PhotoSheetCalculator {
  /// Most columns and rows of [w] × [h] mm items that fit on [paper].
  static ({int cols, int rows}) capacity(
    double w,
    double h,
    PhotoPaper paper, {
    double gap = 4,
    double? margin,
  }) {
    final m = margin ?? paper.marginMm;
    int fit(double space, double item) =>
        ((space - 2 * m + gap) / (item + gap)).floor().clamp(0, 99);
    return (cols: fit(paper.widthMm, w), rows: fit(paper.heightMm, h));
  }

  static int full(double w, double h, PhotoPaper paper) {
    final c = capacity(w, h, paper);
    return c.cols * c.rows;
  }

  /// Copies offered: 4 · 8 · 12 · 16 (those that fit) and Full.
  static List<int> counts(double w, double h, PhotoPaper paper) {
    final max = full(w, h, paper);
    return [
      ...const [4, 8, 12, 16].where((n) => n < max),
      if (max > 0) max,
    ];
  }

  /// Items filled row by row from the top-left of a centred grid. A partly
  /// filled sheet keeps the full sheet's grid, so cutting stays the same.
  static List<PlacedItem> layout(PrintItemSpec s) {
    final cap = capacity(
      s.widthMm,
      s.heightMm,
      s.paper,
      gap: s.gapMm,
      margin: s.marginMm,
    );
    final n = s.count.clamp(0, cap.cols * cap.rows);
    if (n == 0) return const [];
    final cols = math.min(cap.cols, n);
    final rows = (n / cap.cols).ceil();
    final groupW = cols * s.widthMm + (cols - 1) * s.gapMm;
    final groupH = rows * s.heightMm + (rows - 1) * s.gapMm;
    final x0 = (s.paper.widthMm - groupW) / 2;
    // Top-aligned on the sheet so the rest of the paper stays usable.
    final y0 = n == cap.cols * cap.rows
        ? (s.paper.heightMm - groupH) / 2
        : s.marginMm;
    return [
      for (var i = 0; i < n; i++)
        PlacedItem(
          x: x0 + (i % cols) * (s.widthMm + s.gapMm),
          y: y0 + (i ~/ cols) * (s.heightMm + s.gapMm),
          w: s.widthMm,
          h: s.heightMm,
        ),
    ];
  }
}
