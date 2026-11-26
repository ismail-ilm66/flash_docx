import 'dart:io';

import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Round 11, section F: Reduce size for pictures.
void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('reduce'));
  tearDown(() => tmp.delete(recursive: true));

  const photo = 'test/fixtures/edges/letter_page.jpg'; // 1200 × 1600

  String out(String name) => p.join(tmp.path, name);

  (int, int) size(String path) {
    final m = cv.imread(path);
    final s = (m.cols, m.rows);
    m.dispose();
    return s;
  }

  test('a photo under 50 KB as JPG, smaller only as far as needed', () {
    final r = pipe.reduceImage(photo, out('a.jpg'), maxBytes: 50 * 1000);
    expect(r.fits, isTrue);
    expect(File(out('a.jpg')).lengthSync(), lessThanOrEqualTo(50 * 1000));
    expect(File(out('a.jpg')).lengthSync(), r.bytes);
  });

  test('an exact upload size: 300 × 300, the centre kept, never shrunk further', () {
    final r = pipe.reduceImage(photo, out('b.jpg'), maxBytes: 50 * 1000, boxW: 300, boxH: 300, exact: true);
    expect(r.fits, isTrue);
    expect(size(out('b.jpg')), (300, 300));
  });

  test('a long side, WebP and PNG', () {
    pipe.reduceImage(photo, out('c.webp'), maxBytes: 100 * 1000, longSide: 1080);
    expect(size(out('c.webp')).$2, lessThanOrEqualTo(1080));
    final png = pipe.reduceImage(photo, out('d.png'), maxBytes: 2000 * 1000);
    expect(png.fits, isTrue);
    expect(File(out('d.png')).readAsBytesSync().sublist(1, 4), 'PNG'.codeUnits);
  });

  test('too small a target: the smallest version, and it says so', () {
    final r = pipe.reduceImage(photo, out('e.jpg'), maxBytes: 2000);
    expect(r.fits, isFalse);
    expect(File(out('e.jpg')).existsSync(), isTrue);
    expect(size(out('e.jpg')).$2, 800, reason: 'down to an 800 px long edge, no further');
  });

  test('no metadata (no location) in the result', () {
    pipe.reduceImage(photo, out('f.jpg'), maxBytes: 500 * 1000);
    final bytes = File(out('f.jpg')).readAsBytesSync();
    // An EXIF block starts with "Exif\0\0" in an APP1 segment.
    expect(String.fromCharCodes(bytes.take(4096)).contains('Exif'), isFalse);
  });
}
