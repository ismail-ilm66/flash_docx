import 'dart:io';
import 'dart:typed_data';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Passport photo backgrounds: a grey wall with a dark "person" disc; the
/// mask marks the disc.
void main() {
  late Directory tmp;
  late String photo;
  late String mask;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bg');
    final img = cv.Mat.fromScalar(1600, 1200, cv.MatType.CV_8UC3, cv.Scalar(120, 125, 130));
    cv.circle(img, cv.Point(600, 800), 300, cv.Scalar(60, 70, 110), thickness: -1);
    photo = p.join(tmp.path, 'face.jpg');
    cv.imwrite(photo, img);
    img.dispose();
    // The segmenter's mask is smaller than the photo (800 px long).
    final m = Uint8List(600 * 800);
    for (var y = 0; y < 800; y++) {
      for (var x = 0; x < 600; x++) {
        final dx = x - 300;
        final dy = y - 400;
        if (dx * dx + dy * dy < 150 * 150) m[y * 600 + x] = 255;
      }
    }
    mask = p.join(tmp.path, 'mask.png');
    pipe.writeGray(m, 600, 800, mask);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<int> px(cv.Mat m, int y, int x) {
    final v = m.at<cv.Vec3b>(y, x);
    return [v.val1, v.val2, v.val3];
  }

  test('white and light blue replace the wall, not the person', () {
    for (final (bg, want) in [
      (PhotoBackground.white, [255, 255, 255]),
      (PhotoBackground.lightBlue, [245, 227, 207]),
    ]) {
      final out = pipe.renderEdits(
        photo,
        PageEdits(filter: FilterType.original, photoBackground: bg, backgroundMaskPath: mask),
      );
      expect(px(out, 50, 50), want, reason: '$bg: wall');
      final face = px(out, 800, 600);
      expect((face[0] - 60).abs() + (face[1] - 70).abs() + (face[2] - 110).abs(), lessThan(12), reason: '$bg: person kept');
      out.dispose();
    }
  });

  test('the mask follows the crop', () {
    // A 35:45 crop around the disc, off-centre in the photo.
    const crop = Quad(tl: Pt(0.2, 0.25), tr: Pt(0.8, 0.25), br: Pt(0.8, 0.75), bl: Pt(0.2, 0.75));
    final out = pipe.renderEdits(
      photo,
      PageEdits(crop: crop, filter: FilterType.original, outputAspect: 35 / 45, photoBackground: PhotoBackground.white, backgroundMaskPath: mask),
    );
    final cy = out.rows ~/ 2;
    final cx = out.cols ~/ 2;
    expect(px(out, cy, cx), isNot([255, 255, 255]), reason: 'the person is still in the middle');
    expect(px(out, 4, 4), [255, 255, 255]);
    out.dispose();
  });

  test('the edge is feathered, not a hard cut', () {
    final out = pipe.renderEdits(
      photo,
      PageEdits(filter: FilterType.original, photoBackground: PhotoBackground.white, backgroundMaskPath: mask),
    );
    // Along a row through the disc's left edge (x = 300) values ramp.
    final row = [for (var x = 290; x <= 310; x++) px(out, 800, x)[0]];
    final mid = row.where((v) => v > 70 && v < 245);
    expect(mid, isNotEmpty);
    out.dispose();
  });

  test('original, or a missing mask, leaves the photo alone', () {
    final a = pipe.renderEdits(photo, const PageEdits(filter: FilterType.original));
    final b = pipe.renderEdits(photo, PageEdits(filter: FilterType.original, photoBackground: PhotoBackground.white, backgroundMaskPath: p.join(tmp.path, 'gone.png')));
    expect(px(b, 50, 50), px(a, 50, 50));
    a.dispose();
    b.dispose();
  });
}
