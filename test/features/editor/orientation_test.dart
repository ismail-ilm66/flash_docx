import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/utils/exif_orientation.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart';
import 'package:flash_dox/features/ocr/domain/text_recognizer.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
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
class _MarkerOcr implements TextRecognizer {
  @override
  Future<Either<Failure, String>> read(String imagePath) async {
    final m = cv.imread(imagePath);
    final up = markerSide(m) == 'top';
    m.dispose();
    return Right(up ? 'PAKISTAN NATIONAL IDENTITY CARD 35202' : 'q');
  }

  @override
  Future<void> dispose() async {}
}

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

        final rewritten = pipe.bakeOrientation(path);
        expect(rewritten, o != 1, reason: 'upright files are left byte-for-byte');
        expect(readJpegOrientation(path), 1);
        final again = pipe.readUpright(path);
        expect(markerSide(again), 'top', reason: 'never rotated twice');
        again.dispose();
      });
    }

    test('reduced-size reads apply the tag too', () {
      final up = uprightWithMarker(w: 2400, h: 1600);
      final path = writeWithExif(up, p.join(tmp.path, 'big6.jpg'), 6);
      up.dispose();
      final read = pipe.readUprightAtMost(path, 600);
      expect(read.cols, greaterThan(read.rows));
      expect(markerSide(read), 'top');
      read.dispose();
    });

    test('ingest bakes the tag and detects on the upright image', () {
      final up = uprightWithMarker();
      final path = writeWithExif(up, p.join(tmp.path, 'ingest8.jpg'), 8);
      up.dispose();
      final r = ingestInIsolate(IngestMsg(path, p.join(tmp.path, 'prev.jpg'), null, null));
      expect((r.width, r.height), (600, 400));
      expect(readJpegOrientation(path), 1);
      final prev = cv.imread(p.join(tmp.path, 'prev.jpg'));
      expect(markerSide(prev), 'top');
      prev.dispose();
    });
  });

  group('phone held landscape', () {
    test('device orientation maps to clockwise turns', () {
      expect(deviceTurns(DeviceOrientation.portraitUp), 0);
      expect(deviceTurns(DeviceOrientation.landscapeRight), 1);
      expect(deviceTurns(DeviceOrientation.portraitDown), 2);
      expect(deviceTurns(DeviceOrientation.landscapeLeft), 3);
    });

    test('the turns are baked in at ingest', () {
      // Phone turned counter-clockwise: the locked-portrait photo has world-up
      // on its right, i.e. the marker is on the right.
      final up = uprightWithMarker();
      final stored = cv.rotate(up, cv.ROTATE_90_CLOCKWISE);
      final path = p.join(tmp.path, 'land.jpg');
      pipe.writeJpeg(stored, path, quality: 95);
      up.dispose();
      stored.dispose();
      expect(markerSide(pipe.readUpright(path)), 'right');
      ingestInIsolate(IngestMsg(path, p.join(tmp.path, 'prev2.jpg'), null, null, deviceTurns(DeviceOrientation.landscapeLeft)));
      final read = pipe.readUpright(path);
      expect(markerSide(read), 'top');
      read.dispose();
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

  test('ID cards are turned the right way up using text recognition', () async {
    PathProviderPlatform.instance = _Paths(tmp);
    SharedPreferences.setMockInitialValues({});
    final files = FileStore();
    await files.init();
    final prefs = PrefsService(await SharedPreferences.getInstance());
    final prepare = PreparePages(OpenCvImageProcessor(IsolateRunner()), files, prefs, _MarkerOcr());

    // A landscape card photographed upside down: the marker is at the bottom.
    final card = cv.Mat.fromScalar(1000, 1400, cv.MatType.CV_8UC3, cv.Scalar.all(40));
    final face = uprightWithMarker(w: 856, h: 540);
    final flipped = cv.rotate(face, cv.ROTATE_180);
    final roi = card.region(cv.Rect(272, 230, 856, 540));
    flipped.copyTo(roi);
    final src = p.join(tmp.path, 'card.jpg');
    pipe.writeJpeg(card, src, quality: 95);
    for (final m in [card, face, flipped, roi]) {
      m.dispose();
    }

    final r = await prepare([src], mode: ScanMode.idCard, sides: [CardSide.front]);
    final page = r.getOrElse((f) => fail('$f')).single;
    expect(page.edits.normalizedTurns, 2);
    expect(page.side, CardSide.front);

    final out = pipe.renderEdits(page.originalPath, page.edits.copyWith(filter: FilterType.original), maxLongEdge: 800);
    expect(out.cols, greaterThan(out.rows), reason: 'landscape');
    expect(markerSide(out), 'top');
    out.dispose();
  });
}
