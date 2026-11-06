import 'dart:io';
import 'dart:typed_data';

import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:opencv_dart/opencv.dart' as cv;

/// A white 600 × 400 "page" with a black "up" marker centred at the top.
cv.Mat uprightWithMarker({int w = 600, int h = 400}) {
  final m = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar.all(255));
  cv.rectangle(m, cv.Rect(w ~/ 2 - 40, (h * 0.12).round(), 80, (h * 0.1).round()), cv.Scalar.all(0), thickness: -1);
  return m;
}

/// Where the marker is: 'top', 'bottom', 'left' or 'right'. Ignores an 8 %
/// margin so a thin rim of background around a crop doesn't count.
String markerSide(cv.Mat bgr) {
  final mx = (bgr.cols * 0.08).round();
  final my = (bgr.rows * 0.08).round();
  final inner = bgr.region(cv.Rect(mx, my, bgr.cols - 2 * mx, bgr.rows - 2 * my));
  final gray = cv.cvtColor(inner, cv.COLOR_BGR2GRAY);
  inner.dispose();
  final (_, dark) = cv.threshold(gray, 100, 255, cv.THRESH_BINARY_INV);
  final r = cv.boundingRect(cv.VecPoint.fromMat(cv.findNonZero(dark)));
  final cx = (mx + r.x + r.width / 2) / bgr.cols;
  final cy = (my + r.y + r.height / 2) / bgr.rows;
  gray.dispose();
  dark.dispose();
  if (cy < 0.25) return 'top';
  if (cy > 0.75) return 'bottom';
  return cx < 0.5 ? 'left' : 'right';
}

/// Writes [upright] as a JPEG whose pixels are stored so that a viewer that
/// applies EXIF [orientation] shows it upright, with that tag in an APP1
/// segment — what phones produce.
String writeWithExif(cv.Mat upright, String path, int orientation) {
  // Inverse of the display transform for the orientations under test.
  final stored = switch (orientation) {
    3 => cv.rotate(upright, cv.ROTATE_180),
    6 => cv.rotate(upright, cv.ROTATE_90_COUNTERCLOCKWISE),
    8 => cv.rotate(upright, cv.ROTATE_90_CLOCKWISE),
    _ => upright.clone(),
  };
  final tmp = '$path.raw.jpg';
  pipe.writeJpeg(stored, tmp, quality: 95);
  stored.dispose();
  final jpeg = File(tmp).readAsBytesSync();
  File(tmp).deleteSync();
  final app1 = <int>[
    0xFF, 0xE1, 0x00, 0x22, // APP1, length 34
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF II, IFD0 at 8
    0x01, 0x00, // 1 entry
    0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, orientation, 0x00, 0x00, 0x00, // 0x0112 SHORT
    0x00, 0x00, 0x00, 0x00, // next IFD
  ];
  File(path).writeAsBytesSync(Uint8List.fromList([...jpeg.sublist(0, 2), ...app1, ...jpeg.sublist(2)]));
  return path;
}
