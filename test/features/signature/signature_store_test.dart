import 'dart:io';
import 'dart:typed_data';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/signature/data/signature_store.dart';
import 'package:flash_dox/features/signature/domain/catmull_rom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

void main() {
  group('Catmull-Rom', () {
    test('passes through every sampled point, smoother in between', () {
      const pts = [Offset.zero, Offset(10, 10), Offset(20, 0), Offset(30, 10)];
      final out = catmullRom(pts, steps: 4);
      expect(out.length, 1 + 3 * 4);
      for (final (i, pt) in pts.indexed) {
        expect(out[i * 4], pt);
      }
      // A quarter of the way from (10,10) to (20,0) the curve rounds the
      // corner: above the straight line's 7.5.
      expect(out[5].dy, closeTo(8.44, 0.01));
    });

    test('short strokes are returned as they are', () {
      expect(catmullRom(const [Offset(1, 2)]), const [Offset(1, 2)]);
      expect(catmullRom(const [Offset(1, 2), Offset(3, 4)]), const [Offset(1, 2), Offset(3, 4)]);
    });
  });

  group('PageEdits overlays', () {
    test('round-trip through JSON; old JSON without overlays still reads', () {
      const e = PageEdits(
        overlays: [
          PageOverlay(id: 'a', kind: OverlayKind.date, imagePath: '/d/x.png', left: 0.6, top: 0.8, width: 0.3, height: 0.05, ink: InkColor.black),
        ],
      );
      expect(PageEdits.fromJson(e.toJson()), e);
      expect(PageEdits.fromJson(const {'filter': 'auto'}).overlays, isEmpty);
    });
  });

  group('SignatureStore', () {
    late Directory tmp;
    late SignatureStore store;
    late FileStore files;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sigstore');
      PathProviderPlatform.instance = _Paths(tmp);
      SharedPreferences.setMockInitialValues({});
      files = FileStore();
      await files.init();
      store = SignatureStore(files, PrefsService(await SharedPreferences.getInstance()));
    });
    tearDown(() => tmp.delete(recursive: true));

    test('save, adopt into a document, delete; placed copies survive', () async {
      expect(store.saved.value, isFalse);
      expect(store.defaultInk, InkColor.blue);
      await store.save(Uint8List.fromList([1, 2, 3]), ink: InkColor.black);
      expect(store.saved.value, isTrue);
      expect(store.defaultInk, InkColor.black);

      final placed = await store.adoptInto('doc');
      expect(p.isWithin(files.docDir('doc').path, placed), isTrue);
      expect(File(placed).readAsBytesSync(), [1, 2, 3]);
      final date = await store.adoptInto('doc', png: Uint8List.fromList([9]));
      expect(File(date).readAsBytesSync(), [9]);

      await store.delete();
      expect(store.saved.value, isFalse);
      expect(File(store.path).existsSync(), isFalse);
      expect(File(placed).existsSync(), isTrue, reason: 'signed pages keep their signature');
    });
  });
}
