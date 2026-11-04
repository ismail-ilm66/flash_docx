import 'dart:convert';
import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs the detector over real photos in `test/fixtures/edges/` (see the
/// README there). Skipped until fixtures exist.
void main() {
  final dir = Directory('test/fixtures/edges');
  final images = dir.existsSync()
      ? dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.jpg')).toList()
      : <File>[];
  final cases = <(File, Map<String, dynamic>)>[];
  for (final img in images) {
    final side = File(p.setExtension(img.path, '.json'));
    if (!side.existsSync()) continue;
    final meta = jsonDecode(side.readAsStringSync()) as Map<String, dynamic>;
    if (meta['skip'] == true) continue;
    cases.add((img, meta));
  }

  test(
    'at least 26 of 30 fixtures detect every corner within 3%',
    () {
      var passed = 0;
      final failures = <String>[];
      for (final (img, meta) in cases) {
        Pt pt(String k) => Pt((meta[k] as List)[0] as double, (meta[k] as List)[1] as double);
        final expected = Quad(tl: pt('tl'), tr: pt('tr'), br: pt('br'), bl: pt('bl'));
        final mat = pipe.readUpright(img.path);
        final aspect = (meta['aspect'] as num?)?.toDouble();
        final sw = Stopwatch()..start();
        final quad = pipe.detectDocumentQuad(mat, snapAspectRatio: aspect);
        sw.stop();
        mat.dispose();
        var ok = quad != null;
        if (ok) {
          for (var i = 0; i < 4; i++) {
            if ((quad.points[i].x - expected.points[i].x).abs() > 0.03 ||
                (quad.points[i].y - expected.points[i].y).abs() > 0.03) {
              ok = false;
            }
          }
        }
        if (ok) {
          passed++;
        } else {
          failures.add('${p.basename(img.path)} → ${quad ?? 'none'} (${sw.elapsedMilliseconds} ms)');
        }
      }
      // ignore: avoid_print
      print('edge fixtures: $passed / ${cases.length} passed\n${failures.join('\n')}');
      expect(passed, greaterThanOrEqualTo((cases.length * 26 / 30).ceil()));
    },
    skip: cases.isEmpty ? 'no fixtures in test/fixtures/edges' : null,
  );
}
