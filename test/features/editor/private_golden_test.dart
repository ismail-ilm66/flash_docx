import 'dart:convert';
import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;

/// Round 11, P0-10: the owner's own photos (tube light, hand shadow; an
/// angled prescription) against the Python reference. They are private
/// documents, so they live in test/fixtures/private/ (git-ignored) with
/// the outputs of `python3 tool/reference/dump_private.py`; without them
/// this test has nothing to check.
void main() {
  final dir = Directory('test/fixtures/private');
  final photos = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  if (photos.isEmpty) {
    test('private golden photos', () {}, skip: 'no photos in test/fixtures/private');
    return;
  }
  for (final photo in photos) {
    final name = p.basenameWithoutExtension(photo.path);
    test('$name: crop and Auto match the reference', () {
      final meta = jsonDecode(File(p.join(dir.path, '$name.json')).readAsStringSync()) as Map<String, dynamic>;
      final card = meta['mode'] == 'id';
      final img = cv.imread(photo.path);
      final r = pipe.detectDocument(img, aspectHint: card ? 85.6 / 54 : null);
      expect(r.found, isTrue, reason: '$r');
      final expected = [for (final c in meta['corners'] as List) Pt(((c as List)[0] as num).toDouble(), (c[1] as num).toDouble())];
      for (final (i, pt) in r.quad!.points.indexed) {
        expect(pt.x, closeTo(expected[i].x, 0.01), reason: '$name corner $i x');
        expect(pt.y, closeTo(expected[i].y, 0.01), reason: '$name corner $i y');
      }
      final warp = cv.imread(p.join(dir.path, '${name}_warp.png'));
      final got = card ? pipe.idColorFilter(warp) : pipe.autoFilter(warp);
      final want = cv.imread(p.join(dir.path, '${name}_auto.png'));
      expect(got.rows, want.rows);
      expect(got.cols, want.cols);
      final d = cv.absDiff(got, want);
      final m = cv.mean(d);
      final mean = (m.val1 + m.val2 + m.val3) / 3;
      // ignore: avoid_print
      print('$name: ${r.strategy}, Auto mean |Δ| ${mean.toStringAsFixed(2)}');
      expect(mean, lessThanOrEqualTo(3));
      for (final x in [img, warp, got, want, d]) {
        x.dispose();
      }
    });
  }
}
