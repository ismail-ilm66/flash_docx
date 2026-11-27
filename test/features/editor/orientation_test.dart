import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/exif_orientation.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flash_dox/features/scanner/domain/entities/capture_meta.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/exif_jpeg.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

/// "Reads text" only when the probe image is the right way up: the marker
/// (where the card's printing would be) must be at the top.
/// P0-1: photos come out upright whatever EXIF says and however the phone
/// was held; nothing is ever rotated twice.
void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('orient'));
  tearDown(() => tmp.delete(recursive: true));

  group('EXIF', () {
    for (final o in [1, 3, 6, 8]) {
      test('orientation $o: read upright, then baked so the tag is gone', () {
        final up = uprightWithMarker();
        final path = writeWithExif(up, p.join(tmp.path, 'o$o.jpg'), o);
        up.dispose();
        expect(readJpegOrientation(path), o);

        final read = pipe.readUpright(path);
        expect(markerSide(read), 'top');
        expect((read.cols, read.rows), (600, 400));
        read.dispose();

        final before = File(path).readAsBytesSync();
        pipe.bakeOrientation(path);
        if (o == 1) expect(File(path).readAsBytesSync(), before, reason: 'upright files are left byte-for-byte');
        expect(readJpegOrientation(path), 1);
        final again = pipe.readUpright(path);
        expect(markerSide(again), 'top', reason: 'never rotated twice');
        again.dispose();
      });
    }

    test('round 11c: the tag is written without re-encoding, into a file with or without EXIF', () {
      final up = uprightWithMarker();
      // No EXIF block: one is added in front, the image data stays.
      final plain = p.join(tmp.path, 'plain.jpg');
      final rotated = cv.rotate(up, cv.ROTATE_90_COUNTERCLOCKWISE);
      pipe.writeJpeg(rotated, plain, quality: 95);
      final data = File(plain).readAsBytesSync();
      expect(writeJpegOrientation(plain, 6), isTrue);
      expect(readJpegOrientation(plain), 6);
      final after = File(plain).readAsBytesSync();
      expect(after.sublist(after.length - (data.length - 2)), data.sublist(2), reason: 'image data untouched');
      final read = pipe.readUpright(plain);
      expect(markerSide(read), 'top');
      // A tag already there is changed in place (same length).
      final tagged = writeWithExif(up, p.join(tmp.path, 'tagged.jpg'), 3);
      final len = File(tagged).lengthSync();
      expect(writeJpegOrientation(tagged, 1), isTrue);
      expect(readJpegOrientation(tagged), 1);
      expect(File(tagged).lengthSync(), len);
      expect(pipe.composeOrientation(1, 1), 6);
      expect(pipe.composeOrientation(6, 2), 8);
      for (final m in [up, rotated, read]) {
        m.dispose();
      }
    });

    test('reduced-size reads apply the tag too', () {
      final up = uprightWithMarker(w: 2400, h: 1600);
      final path = writeWithExif(up, p.join(tmp.path, 'big6.jpg'), 6);
      up.dispose();
      final read = pipe.readUprightAtMost(path, 600);
      expect(read.cols, greaterThan(read.rows));
      expect(markerSide(read), 'top');
      read.dispose();
    });

    test('round 11c: ingest keeps the tag (no re-encode) and detects on the upright image', () {
      final up = uprightWithMarker();
      final path = writeWithExif(up, p.join(tmp.path, 'ingest8.jpg'), 8);
      up.dispose();
      final before = File(path).readAsBytesSync();
      final r = ingestInIsolate(IngestMsg(path, p.join(tmp.path, 'prev.jpg'), null, null));
      expect((r.width, r.height), (600, 400));
      expect(File(path).readAsBytesSync(), before);
      expect(readJpegOrientation(path), 8);
      final prev = cv.imread(p.join(tmp.path, 'prev.jpg'));
      expect(markerSide(prev), 'top');
      prev.dispose();
    });
  });

  group('P0-1 capture normalizer: every row of the table', () {
    // Physical model, independent of the code under test: a camera whose
    // sensor is mounted at [sensor]° stores the scene turned back by the
    // rotation Android documents: (sensor − device + 360) % 360 for the back
    // camera, (sensor + device) % 360 for the front. Device degrees: portrait
    // 0, landscape left (top to the left) 90, upside down 180, landscape
    // right 270.
    int neededDegrees(int sensor, int deviceDeg, {required bool front}) =>
        front ? (sensor + deviceDeg) % 360 : (sensor - deviceDeg + 360) % 360;
    // Our deviceTurns for those poses (clockwise turns of a portrait capture).
    int turnsFor(int deviceDeg) => {0: 0, 90: 3, 180: 2, 270: 1}[deviceDeg]!;

    cv.Mat turnedBack(cv.Mat scene, int degrees) => switch (degrees) {
          90 => cv.rotate(scene, cv.ROTATE_90_COUNTERCLOCKWISE),
          180 => cv.rotate(scene, cv.ROTATE_180),
          270 => cv.rotate(scene, cv.ROTATE_90_CLOCKWISE),
          _ => scene.clone(),
        };

    for (final front in [false, true]) {
      final sensor = front ? 270 : 90;
      for (final (pose, deviceDeg) in [('portrait', 0), ('landscape left', 90), ('upside down', 180), ('landscape right', 270)]) {
        test('${front ? 'front' : 'back'} camera, $pose, no EXIF tag, sensor pixels', () {
          // Held portrait the scene is portrait; held sideways, landscape.
          final portrait = deviceDeg % 180 == 0;
          final scene = uprightWithMarker(w: portrait ? 400 : 600, h: portrait ? 600 : 400);
          final raw = turnedBack(scene, neededDegrees(sensor, deviceDeg, front: front));
          expect(raw.cols, greaterThan(raw.rows), reason: 'sensors are landscape');
          final path = p.join(tmp.path, 'raw_${front}_$deviceDeg.jpg');
          pipe.writeJpeg(raw, path, quality: 95);
          for (final m in [scene, raw]) {
            m.dispose();
          }
          expect(readJpegOrientation(path), 1);
          final line = pipe.normalizeCapture(
            path,
            CaptureMeta(sensorOrientation: sensor, deviceTurns: turnsFor(deviceDeg), frontCamera: front),
          );
          expect(line, startsWith('[orient] exif=1'));
          final read = pipe.readUpright(path);
          expect(markerSide(read), 'top', reason: line);
          expect(read.cols < read.rows, portrait);
          read.dispose();
        });
      }
    }

    test('no tag, but the phone already turned the pixels: device only', () {
      // Held landscape left: the phone turned the sensor pixels upright for
      // a portrait UI, so world-up is on the right of the stored image.
      final scene = uprightWithMarker();
      final stored = cv.rotate(scene, cv.ROTATE_90_CLOCKWISE);
      final path = p.join(tmp.path, 'turned.jpg');
      pipe.writeJpeg(stored, path, quality: 95);
      scene.dispose();
      stored.dispose();
      pipe.normalizeCapture(path, const CaptureMeta(sensorOrientation: 90, deviceTurns: 3));
      final read = pipe.readUpright(path);
      expect(markerSide(read), 'top');
      read.dispose();

      final upright = uprightWithMarker(w: 400, h: 600);
      final path2 = p.join(tmp.path, 'portrait.jpg');
      pipe.writeJpeg(upright, path2, quality: 95);
      upright.dispose();
      final before = File(path2).readAsBytesSync();
      pipe.normalizeCapture(path2, const CaptureMeta(sensorOrientation: 90, deviceTurns: 0));
      expect(File(path2).readAsBytesSync(), before, reason: 'nothing to do: untouched');
    });

    test('tagged: the tag, then how the phone was held', () {
      // Held landscape left, sensor pixels with tag 6 (the camera tagged for
      // its portrait UI): after the tag world-up is on the right.
      final scene = uprightWithMarker();
      final afterTag = cv.rotate(scene, cv.ROTATE_90_CLOCKWISE);
      final path = writeWithExif(afterTag, p.join(tmp.path, 'tag6.jpg'), 6);
      scene.dispose();
      afterTag.dispose();
      final line = pipe.normalizeCapture(path, const CaptureMeta(sensorOrientation: 90, deviceTurns: 3));
      expect(readJpegOrientation(path), 1);
      final read = pipe.readUpright(path);
      expect(markerSide(read), 'top', reason: line);
      read.dispose();
    });

    test('imports get the tag only, even when the pixels are landscape', () {
      final scene = uprightWithMarker();
      final path = p.join(tmp.path, 'import.jpg');
      pipe.writeJpeg(scene, path, quality: 95);
      scene.dispose();
      final line = pipe.normalizeCapture(path, null);
      expect(line, contains('import'));
      final read = pipe.readUpright(path);
      expect(markerSide(read), 'top');
      read.dispose();
    });

    test('ingest uses the capture, and turns the guide by the device part', () {
      final scene = uprightWithMarker(w: 400, h: 600);
      final raw = cv.rotate(scene, cv.ROTATE_90_COUNTERCLOCKWISE);
      final path = p.join(tmp.path, 'ingest_raw.jpg');
      pipe.writeJpeg(raw, path, quality: 95);
      scene.dispose();
      raw.dispose();
      final r = ingestInIsolate(
        IngestMsg(path, p.join(tmp.path, 'prev3.jpg'), null, null, const CaptureMeta(sensorOrientation: 90, deviceTurns: 0)),
      );
      expect((r.width, r.height), (400, 600));
      expect(r.orientation, contains('final=90°'));
      final prev = cv.imread(p.join(tmp.path, 'prev3.jpg'));
      expect(markerSide(prev), 'top');
      prev.dispose();
    });

    test('a guide quad turns with the photo', () {
      const guide = Quad(tl: Pt(0.1, 0.3), tr: Pt(0.9, 0.3), br: Pt(0.9, 0.5), bl: Pt(0.1, 0.5));
      final q = guide.rotatedQuarterTurns(1);
      // A landscape strip near the top becomes a portrait strip near the right.
      expect(q.tl.x, closeTo(0.5, 1e-9));
      expect(q.br.x, closeTo(0.7, 1e-9));
      expect(q.tl.y, closeTo(0.1, 1e-9));
      expect(q.br.y, closeTo(0.9, 1e-9));
      expect(guide.rotatedQuarterTurns(4), guide);
    });
  });

  test('round 11c: a card is turned to landscape, with no text recognition while scanning', () async {
    PathProviderPlatform.instance = _Paths(tmp);
    SharedPreferences.setMockInitialValues({});
    final files = FileStore();
    await files.init();
    final prefs = PrefsService(await SharedPreferences.getInstance());
    final prepare = PreparePages(OpenCvImageProcessor(IsolateRunner()), files, prefs);

    // A card photographed with the phone upright: the card is portrait.
    final card = cv.Mat.fromScalar(1400, 1000, cv.MatType.CV_8UC3, cv.Scalar.all(40));
    final face = uprightWithMarker(w: 856, h: 540);
    final turned = cv.rotate(face, cv.ROTATE_90_CLOCKWISE);
    final roi = card.region(cv.Rect(230, 272, 540, 856));
    turned.copyTo(roi);
    final src = p.join(tmp.path, 'card.jpg');
    pipe.writeJpeg(card, src, quality: 95);
    for (final m in [card, face, turned, roi]) {
      m.dispose();
    }

    final r = await prepare([src], mode: ScanMode.idCard, sides: [CardSide.front]);
    final page = r.getOrElse((f) => fail('$f')).single;
    expect(page.edits.normalizedTurns.isOdd, isTrue);
    expect(page.side, CardSide.front);
    final out = pipe.renderEdits(page.originalPath, page.edits.copyWith(filter: FilterType.original), maxLongEdge: 800);
    expect(out.cols, greaterThan(out.rows), reason: 'landscape');
    out.dispose();
  });
}
