import 'dart:io';

import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// One card side as it comes from the document: original photo + edits.
typedef CardSource = ({String originalPath, PageEdits edits});

/// Renders the layout as one image at `dpi` (300 Standard / 600 High),
/// straight from the original photos and encoded once (round 3, A2 / P1-9).
/// The image output is cropped to the cards plus a 6 mm white margin.
@lazySingleton
class SheetImageRenderer {
  SheetImageRenderer(this._runner);

  final IsolateRunner _runner;

  Future<String> render(
    PrintLayoutSpec spec, {
    required CardSource front,
    required String outputPath,
    CardSource? back,
    int dpi = 300,
    int jpegQuality = 92,
  }) =>
      _runner.run(_render, _Msg(spec, front, back, dpi, outputPath, jpegQuality), debugLabel: 'sheetImage');
}

class _Msg {
  const _Msg(this.spec, this.front, this.back, this.dpi, this.out, this.quality);
  final PrintLayoutSpec spec;
  final CardSource front;
  final CardSource? back;
  final int dpi;
  final String out;
  final int quality;
}

String _render(_Msg m) {
  int px(double mm) => (mm / 25.4 * m.dpi).round();
  final layout = PrintLayoutCalculator.layout(m.spec);
  final box = PrintLayoutCalculator.contentBox(layout.pages.first);
  final card = PrintLayoutCalculator.cardSize(m.spec.kind);
  cv.Mat side(CardSource s) =>
      pipe.renderCard(s.originalPath, s.edits, widthMm: card.w, heightMm: card.h, dpi: m.dpi);
  final sheet = cv.Mat.fromScalar(px(box.h), px(box.w), cv.MatType.CV_8UC3, cv.Scalar.all(255));
  final front = side(m.front);
  final back = m.back == null ? null : side(m.back!);
  try {
    for (final it in layout.pages.first) {
      final src = it.isBack ? (back ?? front) : front;
      final w = px(it.w);
      final h = px(it.h);
      final rot = it.rotated ? cv.rotate(src, cv.ROTATE_90_COUNTERCLOCKWISE) : src;
      final placed = cv.resize(
        rot,
        (w, h),
        interpolation: rot.cols > w ? cv.INTER_AREA : cv.INTER_CUBIC,
      );
      if (!identical(rot, src)) rot.dispose();
      final roi = sheet.region(cv.Rect(px(it.x - box.x), px(it.y - box.y), w, h));
      placed.copyTo(roi);
      roi.dispose();
      placed.dispose();
    }
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(sheet, m.out, quality: m.quality);
    return m.out;
  } finally {
    sheet.dispose();
    front.dispose();
    back?.dispose();
  }
}
