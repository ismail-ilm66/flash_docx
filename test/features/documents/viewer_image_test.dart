import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/documents/presentation/cubit/viewer_cubit.dart';
import 'package:flash_dox/features/editor/data/services/preview_cache.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Round 10, P0-3: the viewer never shows the original photo or an
/// unfiltered crop.
void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('viewer_image'));
  tearDown(() => tmp.delete(recursive: true));

  String file(String name) => (File(p.join(tmp.path, name))..writeAsBytesSync([1])).path;

  ScanPage page({String? processed, String? thumb}) => ScanPage(
        id: 'p',
        documentId: 'd',
        originalPath: file('original.jpg'),
        edits: const PageEdits(),
        order: 0,
        processedPath: processed,
        thumbPath: thumb,
      );

  test('display image, then the Enhance look, then the thumbnail softened, else nothing', () {
    final display = file('display.jpg');
    final thumb = file('thumb.jpg');
    final look = file('look.jpg');
    const empty = ViewerState();

    expect(empty.imageFor(page(processed: display, thumb: thumb)), (path: display, blurred: false));

    final withLook = page(thumb: thumb);
    final s = empty.copyWith(quick: {'p': look}, quickVersions: {'p': ViewerState.versionOf(withLook)});
    expect(s.imageFor(withLook), (path: look, blurred: false));

    expect(empty.imageFor(page(thumb: thumb)), (path: thumb, blurred: true));
    expect(empty.imageFor(page(processed: p.join(tmp.path, 'gone.jpg'))), isNull);
  });

  test('round 11, P0-7: Enhance hands its images to the viewer on Done, for exactly that look', () {
    final cache = PreviewCache(_Proc(), FileStore());
    final shown = file('instant.jpg');
    final pg = page();
    cache.handOff(pg.id, pg.edits, shown);
    // The saved page has a new original path (moved into the document).
    expect(cache.handedOff(pg.copyWith(originalPath: file('moved.jpg'))), shown);
    expect(cache.handedOff(pg.withEdits(const PageEdits(filter: FilterType.bwPrint))), isNull, reason: 'another look');
    File(shown).deleteSync();
    expect(cache.handedOff(pg), isNull, reason: 'file gone');
  });
}

class _Proc extends Mock implements ImageProcessor {}
