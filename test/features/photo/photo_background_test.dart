import 'dart:io';
import 'dart:math' as math;
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
      (PhotoBackground.darkBlue, [140, 78, 31]),
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

  test('coverResize: exactly the asked size, centre-cropped, nothing stretched', () {
    final img = cv.imread(photo); // 1200 × 1600
    final square = pipe.coverResize(img, 600, 600);
    expect((square.cols, square.rows), (600, 600));
    // The disc (person) is centred in x and stays round: same width as height.
    final small = pipe.coverResize(img, 413, 531);
    expect((small.cols, small.rows), (413, 531));
    for (final m in [img, square, small]) {
      m.dispose();
    }
  });

  test('a 35 × 45 crop renders portrait 35:45, not stretched to landscape', () {
    // The crop the passport screen makes: 35:45 in pixels of a 3:4 photo.
    const crop = Quad(tl: Pt(0.2, 0.2), tr: Pt(0.8, 0.2), br: Pt(0.8, 0.7), bl: Pt(0.2, 0.7));
    // 0.6 × 1200 = 720 wide, 0.5 × 1600 = 800 tall → close to 35:45 already.
    final out = pipe.renderEdits(photo, const PageEdits(crop: crop, filter: FilterType.original, outputAspect: 35 / 45));
    expect(out.rows, greaterThan(out.cols));
    expect(out.cols / out.rows, closeTo(35 / 45, 0.01));
    out.dispose();
    final square = pipe.renderEdits(photo, const PageEdits(crop: crop, filter: FilterType.original, outputAspect: 1));
    expect(square.cols / square.rows, closeTo(1, 0.01));
    square.dispose();
  });

  test('a photo saved as light blue (first build) still loads, as dark blue', () {
    final e = PageEdits.fromJson(const {'photoBackground': 'lightBlue'});
    expect(e.photoBackground, PhotoBackground.darkBlue);
  });

  group('edges (round 5 feedback: white fringe on dark blue)', () {
    // Head and shoulders on a white wall; the mask is ML Kit-like: low
    // resolution and a few px too generous.
    const w = 531;
    const h = 683;
    late cv.Mat truth;
    late cv.Mat coarse;

    cv.Mat person({bool whiteShirt = false}) {
      final img = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar(232, 236, 238));
      void shape(cv.Mat m, cv.Scalar c) {
        cv.ellipse(m, cv.Point(265, 300), cv.Point(150, 190), 0, 0, 360, c, thickness: -1, lineType: cv.LINE_AA);
        cv.ellipse(m, cv.Point(265, 760), cv.Point(300, 230), 0, 0, 360, c, thickness: -1, lineType: cv.LINE_AA);
      }

      shape(img, cv.Scalar(38, 32, 30));
      if (whiteShirt) {
        cv.ellipse(img, cv.Point(265, 760), cv.Point(300, 230), 0, 0, 360, cv.Scalar(246, 247, 248), thickness: -1, lineType: cv.LINE_AA);
        cv.ellipse(img, cv.Point(265, 760), cv.Point(120, 200), 0, 0, 360, cv.Scalar(38, 32, 30), thickness: -1, lineType: cv.LINE_AA);
      }
      cv.ellipse(img, cv.Point(265, 330), cv.Point(95, 125), 0, 0, 360, cv.Scalar(140, 165, 205), thickness: -1, lineType: cv.LINE_AA);
      truth = cv.Mat.zeros(h, w, cv.MatType.CV_8UC1);
      shape(truth, cv.Scalar.all(255));
      final small = cv.resize(truth, (64, 82), interpolation: cv.INTER_AREA);
      final blurred = cv.gaussianBlur(small, (0, 0), 1.2);
      coarse = blurred.convertTo(cv.MatType.CV_8UC1, alpha: 1.4);
      small.dispose();
      blurred.dispose();
      return img;
    }

    test('no pale fringe around dark hair and clothes', () {
      final img = person();
      final out = pipe.replaceBackground(img, coarse, pipe.photoBackgroundColor(PhotoBackground.darkBlue)!);
      final gray = cv.cvtColor(out, cv.COLOR_BGR2GRAY);
      final k = cv.getStructuringElement(cv.MORPH_ELLIPSE, (41, 41));
      final grown = cv.dilate(truth, k);
      final shrunk = cv.erode(truth, k);
      var bright = 0;
      var total = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (grown.at<int>(y, x) == shrunk.at<int>(y, x)) continue;
          final fx = (x - 265) / 105;
          final fy = (y - 330) / 135;
          if (fx * fx + fy * fy < 1) continue; // the face is light on purpose
          total++;
          // Hair ≈ 32, dark blue ≈ 71: anything well above is wall showing.
          if (gray.at<int>(y, x) > 110) bright++;
        }
      }
      // The plain feathered blend left ~22 % of this ring pale.
      expect(bright / total, lessThan(0.005), reason: '$bright of $total pale');
      for (final m in [img, out, gray, k, grown, shrunk, truth, coarse]) {
        m.dispose();
      }
    });

    test('a white shirt beside a dark jacket is not taken for wall', () {
      final img = person(whiteShirt: true);
      final out = pipe.replaceBackground(img, coarse, pipe.photoBackgroundColor(PhotoBackground.darkBlue)!);
      // Shirt just above the jacket, near the outline: once turned blue.
      for (final x in [200, 265, 330]) {
        expect(px(out, 548, x).reduce(math.min), greaterThan(200), reason: 'shirt at x $x');
      }
      expect(px(out, 40, 40), [140, 78, 31], reason: 'wall');
      for (final m in [img, out, truth, coarse]) {
        m.dispose();
      }
    });
  });

  group('Enhance', () {
    // Head and shoulders: skin face, dark hair and jacket, white teeth-like
    // highlight; [cast] tints the whole photo like room light.
    const w = 413;
    const h = 531;

    (cv.Mat, cv.Mat) portrait({
      required cv.Scalar skin,
      double exposure = 1,
      List<double> cast = const [1, 1, 1],
    }) {
      final img = cv.Mat.fromScalar(
        h,
        w,
        cv.MatType.CV_8UC3,
        cv.Scalar(214, 216, 218),
      );
      final mask = cv.Mat.zeros(h, w, cv.MatType.CV_8UC1);
      void head(cv.Mat m, cv.Scalar hair, cv.Scalar face, cv.Scalar jacket) {
        cv.ellipse(
          m,
          cv.Point(206, 560),
          cv.Point(220, 170),
          0,
          0,
          360,
          jacket,
          thickness: -1,
        );
        cv.ellipse(
          m,
          cv.Point(206, 230),
          cv.Point(130, 165),
          0,
          0,
          360,
          hair,
          thickness: -1,
        );
        cv.ellipse(
          m,
          cv.Point(206, 260),
          cv.Point(100, 130),
          0,
          0,
          360,
          face,
          thickness: -1,
        );
      }

      head(img, cv.Scalar(30, 32, 36), skin, cv.Scalar(90, 50, 20));
      cv.rectangle(
        img,
        cv.Rect(180, 320, 52, 10),
        cv.Scalar(240, 240, 240),
        thickness: -1,
      ); // teeth
      head(mask, cv.Scalar.all(255), cv.Scalar.all(255), cv.Scalar.all(255));
      final f = img.convertTo(cv.MatType.CV_32FC3, alpha: exposure);
      final tinted = cv.multiply(
        f,
        cv.Mat.fromScalar(
          h,
          w,
          cv.MatType.CV_32FC3,
          cv.Scalar(cast[0], cast[1], cast[2]),
        ),
      );
      final out = tinted.convertTo(cv.MatType.CV_8UC3);
      for (final m in [img, f, tinted]) {
        m.dispose();
      }
      return (out, mask);
    }

    double luma(cv.Mat img, cv.Rect r) {
      final roi = img.region(r);
      final m = cv.mean(roi);
      roi.dispose();
      return 0.114 * m.val1 + 0.587 * m.val2 + 0.299 * m.val3;
    }

    final cheek = cv.Rect(140, 230, 40, 40);
    final wallBox = cv.Rect(5, 5, 50, 50);
    final jacketBox = cv.Rect(30, 500, 40, 25);

    test('off leaves the photo alone', () {
      final (img, mask) = portrait(skin: cv.Scalar(120, 150, 200));
      expect(identical(pipe.finishPhoto(img, mask), img), isTrue);
      final out = pipe.enhancePhoto(img, mask, PhotoEnhance.off);
      expect(cv.norm1(out, img), 0);
      for (final m in [img, mask, out]) {
        m.dispose();
      }
    });

    test(
      'a dark, warm indoor photo: brighter, and the wall is neutral again',
      () {
        final (img, mask) = portrait(
          skin: cv.Scalar(120, 150, 200),
          exposure: 0.6,
          cast: const [0.8, 0.95, 1.12],
        );
        final out = pipe.enhancePhoto(img, mask, PhotoEnhance.natural);
        expect(
          luma(out, cheek),
          greaterThan(luma(img, cheek) + 15),
          reason: 'brighter face',
        );
        double cast(cv.Mat m) {
          final roi = m.region(wallBox);
          final v = cv.mean(roi);
          roi.dispose();
          return v.val3 - v.val1; // red minus blue
        }

        expect(
          cast(out).abs(),
          lessThan(cast(img).abs() / 3),
          reason: 'wall ${cast(img)} → ${cast(out)}',
        );
        for (final m in [img, mask, out]) {
          m.dispose();
        }
      },
    );

    test(
      'a well-lit photo: darker skin is not lightened, dark clothes keep their tone',
      () {
        final (img, mask) = portrait(skin: cv.Scalar(60, 85, 120));
        final out = pipe.enhancePhoto(img, mask, PhotoEnhance.natural);
        expect(
          (luma(out, cheek) - luma(img, cheek)).abs(),
          lessThan(6),
          reason: 'skin tone kept',
        );
        expect(
          (luma(out, jacketBox) - luma(img, jacketBox)).abs(),
          lessThan(6),
          reason: 'jacket kept',
        );
        for (final m in [img, mask, out]) {
          m.dispose();
        }
      },
    );

    test(
      'soft smooths skin more than natural; both keep the face where it was',
      () {
        final (base, mask) = portrait(skin: cv.Scalar(120, 150, 200));
        // Skin texture: fine noise on the face only.
        final noise = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
        cv.randn(noise, cv.Scalar.all(0), cv.Scalar.all(12));
        final img = cv.add(base, noise);
        double texture(cv.Mat m) {
          final roi = m.region(cheek);
          final (_, sd) = cv.meanStdDev(roi);
          roi.dispose();
          return sd.val2;
        }

        final natural = pipe.enhancePhoto(img, mask, PhotoEnhance.natural);
        final soft = pipe.enhancePhoto(img, mask, PhotoEnhance.smooth);
        expect(texture(natural), lessThan(texture(img)));
        expect(texture(soft), lessThan(texture(natural)));
        expect(
          texture(natural),
          greaterThan(0.2 * texture(img)),
          reason: 'texture kept, not plastic',
        );
        for (final m in [base, mask, noise, img, natural, soft]) {
          m.dispose();
        }
      },
    );

    test('old edits read as Off; a new choice round-trips', () {
      expect(PageEdits.fromJson(const {}).photoEnhance, PhotoEnhance.off);
      expect(
        PageEdits.fromJson(const {'photoEnhance': 'sparkle'}).photoEnhance,
        PhotoEnhance.off,
      );
      const e = PageEdits(photoEnhance: PhotoEnhance.smooth);
      expect(PageEdits.fromJson(e.toJson()).photoEnhance, PhotoEnhance.smooth);
    });
  });

  group('sharp mask from the crop', () {
    test(
      'Quad.bounds: the box around the crop plus a margin, inside the photo',
      () {
        final q = Quad.fromUnordered(const [
          Pt(0.2, 0.1),
          Pt(0.6, 0.1),
          Pt(0.6, 0.5),
          Pt(0.2, 0.5),
        ]);
        final b = q.bounds(margin: 0.25);
        expect(
          [b.left, b.top, b.right, b.bottom].map((v) => (v * 100).round()),
          [10, 0, 70, 60],
        );
      },
    );

    test('writeRegion cuts the crop out at the segmentation size (crashed on every phone photo)', () {
      // A crop bigger than the asked size, so it is shrunk: the case that
      // freed the crop twice.
      final out = p.join(tmp.path, 'region.jpg');
      final (w, h) = pipe.writeRegion(photo, (left: 0.25, top: 0.25, right: 0.75, bottom: 0.75), 400, out);
      expect((w, h), (300, 400));
      final m = cv.imread(out);
      expect((m.cols, m.rows), (300, 400));
      m.dispose();
    });

    test(
      'composeMask pastes the crop mask over the scaled-up whole-photo mask',
      () {
        final base = p.join(tmp.path, 'coarse.png');
        // Coarse: whole photo 100 × 200, left half person.
        final coarse = Uint8List(100 * 200);
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 50; x++) {
            coarse[y * 100 + x] = 255;
          }
        }
        pipe.writeGray(coarse, 100, 200, base);
        // Sharp: the region x 0.5–0.75, y 0.25–0.5 at 80 × 160, all person.
        final sharp = Uint8List(80 * 160)..fillRange(0, 80 * 160, 255);
        final out = p.join(tmp.path, 'composed.png');
        pipe.composeMask(base, sharp, 80, 160, (
          left: 0.5,
          top: 0.25,
          right: 0.75,
          bottom: 0.5,
        ), out);
        final m = cv.imread(out, flags: cv.IMREAD_GRAYSCALE);
        expect(
          (m.cols, m.rows),
          (320, 640),
          reason: 'the region keeps its resolution',
        );
        expect(m.at<int>(320, 100), 255, reason: 'coarse person, scaled up');
        expect(m.at<int>(240, 200), 255, reason: 'the sharp region');
        expect(
          m.at<int>(100, 200),
          0,
          reason: 'coarse background above the region',
        );
        expect(m.at<int>(320, 300), 0, reason: 'coarse background beside it');
        m.dispose();
      },
    );
  });

  group('a 12 MP phone photo (the crash after Next)', () {
    // 3000 × 4000 with a person, the passport crop a third of it; dark blue
    // and Natural, like a fresh passport photo.
    late String big;
    late String bigMask;
    const crop = Quad(tl: Pt(0.32, 0.19), tr: Pt(0.68, 0.19), br: Pt(0.68, 0.53), bl: Pt(0.32, 0.53));

    setUp(() {
      final img = cv.Mat.fromScalar(4000, 3000, cv.MatType.CV_8UC3, cv.Scalar(214, 216, 218));
      final m = cv.Mat.zeros(4000, 3000, cv.MatType.CV_8UC1);
      for (final (mat, colour) in [(img, cv.Scalar(60, 90, 140)), (m, cv.Scalar.all(255))]) {
        cv.ellipse(mat, cv.Point(1500, 1400), cv.Point(380, 500), 0, 0, 360, colour, thickness: -1);
        cv.ellipse(mat, cv.Point(1500, 3300), cv.Point(1100, 1300), 0, 0, 360, colour, thickness: -1);
      }
      big = p.join(tmp.path, 'big.jpg');
      bigMask = p.join(tmp.path, 'big_mask.png');
      cv.imwrite(big, img);
      cv.imwrite(bigMask, cv.resize(m, (600, 800), interpolation: cv.INTER_AREA));
      img.dispose();
      m.dispose();
    });

    PageEdits edits() => PageEdits(
      crop: crop,
      outputAspect: 35 / 45,
      photoWidthMm: 35,
      photoHeightMm: 45,
      photoBackground: PhotoBackground.darkBlue,
      photoEnhance: PhotoEnhance.natural,
      backgroundMaskPath: bigMask,
    );

    // First in the group: the process's peak memory only ever grows, so a
    // big render before this would hide the growth it measures.
    test('rendering it never needs gigabytes', () {
      final before = ProcessInfo.maxRss;
      for (final out in [
        pipe.renderSized(big, edits(), widthMm: 35, heightMm: 45, dpi: 300),
        pipe.renderEdits(big, edits()),
      ]) {
        expect(math.max(out.cols, out.rows), lessThanOrEqualTo(pipe.photoFinishLongEdge));
        out.dispose();
      }
      // Was +1.1 GB (every step at the camera's full resolution, all kept
      // to the end): Android killed the app.
      final grew = (ProcessInfo.maxRss - before) / 1e6;
      expect(grew, lessThan(600), reason: '+${grew.round()} MB');
    });

    test('the print render is exactly the print size', () {
      final out = pipe.renderSized(big, edits(), widthMm: 35, heightMm: 45, dpi: 300);
      expect((out.cols, out.rows), (413, 531));
      out.dispose();
    });
  });
}
