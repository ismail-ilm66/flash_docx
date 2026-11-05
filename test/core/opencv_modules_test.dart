import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;

/// The native build must include every OpenCV module the pipeline calls
/// (see `hooks.user_defines.dartcv4.include_modules` in pubspec.yaml).
void main() {
  test('photo module (non-local means) is linked', () {
    final m = cv.Mat.fromScalar(32, 32, cv.MatType.CV_8UC3, cv.Scalar(100, 120, 140));
    final out = cv.fastNlMeansDenoisingColored(m, h: 5, hColor: 5);
    expect(out.cols, 32);
    out.dispose();
    m.dispose();
  });

  test('imgproc line detection and Laplacian are linked', () {
    final m = cv.Mat.zeros(64, 64, cv.MatType.CV_8UC1);
    cv.line(m, cv.Point(5, 32), cv.Point(60, 32), cv.Scalar.all(255), thickness: 2);
    final lines = cv.HoughLinesP(m, 1, 3.14159 / 180, 20, minLineLength: 20, maxLineGap: 5);
    expect(lines.rows, greaterThan(0));
    final lap = cv.laplacian(m, cv.MatType.CV_64F);
    expect(lap.isEmpty, isFalse);
    for (final x in [m, lines, lap]) {
      x.dispose();
    }
  });
}
