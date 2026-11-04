import 'dart:io';

import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/print_layout/domain/entities/print_layout_spec.dart';
import 'package:flash_dox/features/print_layout/domain/print_layout_calculator.dart';
import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// Renders the A4 sheet layout as a 300 DPI image (JPG or PNG by extension).
@lazySingleton
class SheetImageRenderer {
  SheetImageRenderer(this._runner);

  final IsolateRunner _runner;

  Future<String> render(PrintLayoutSpec spec, {required String outputPath}) =>
      _runner.run(_render, _Msg(spec, outputPath), debugLabel: 'sheetImage');
}

class _Msg {
  const _Msg(this.spec, this.out);
  final PrintLayoutSpec spec;
  final String out;
}

String _render(_Msg m) {
  const dpi = RenderPx.printDpi;
  int px(double mm) => (mm / 25.4 * dpi).round();
  final layout = PrintLayoutCalculator.layout(m.spec);
  final sheetW = px(PrintLayoutCalculator.sheetW);
  final sheetH = px(PrintLayoutCalculator.sheetH);
  final sheet = cv.Mat.fromScalar(sheetH, sheetW, cv.MatType.CV_8UC3, cv.Scalar.all(255));
  final front = pipe.readUpright(m.spec.frontPath);
  final back = m.spec.backPath == null ? null : pipe.readUpright(m.spec.backPath!);
  try {
    for (final it in layout.pages.first) {
      var src = it.isBack ? (back ?? front) : front;
      final w = px(it.w);
      final h = px(it.h);
      cv.Mat placed;
      if (it.rotated) {
        final rot = cv.rotate(src, cv.ROTATE_90_COUNTERCLOCKWISE);
        placed = cv.resize(rot, (w, h), interpolation: cv.INTER_AREA);
        rot.dispose();
      } else {
        placed = cv.resize(src, (w, h), interpolation: cv.INTER_AREA);
      }
      final roi = sheet.region(cv.Rect(px(it.x), px(it.y), w, h));
      placed.copyTo(roi);
      roi.dispose();
      placed.dispose();
      src = front; // keep analyzer quiet about reassignment
    }
    File(m.out).parent.createSync(recursive: true);
    pipe.writeJpeg(sheet, m.out, quality: 92);
    return m.out;
  } finally {
    sheet.dispose();
    front.dispose();
    back?.dispose();
  }
}
