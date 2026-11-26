import 'dart:io';

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/features/editor/data/opencv/pipeline.dart' as pipe;
import 'package:flash_dox/features/export/data/footer_artwork.dart';
import 'package:flash_dox/features/export/data/pdf_builder_impl.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/entities/page_footer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

/// Round 10, P1-6: the footer as it really draws.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FileStore files;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('footer');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
  });
  tearDown(() => tmp.delete(recursive: true));

  String page(String name, {int w = 2000, int h = 2828}) {
    final m = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, cv.Scalar(60, 60, 60)); // dark content to the edge
    final path = p.join(tmp.path, '$name.jpg');
    pipe.writeJpeg(m, path, quality: 90);
    m.dispose();
    return path;
  }

  testWidgets('round 11: a JPG page gets a white strip (4 %) with the badge, the scan untouched', (tester) async {
    final out = await tester.runAsync(() async {
      // The app's fonts, as on the phone (tests default to Ahem boxes).
      for (final w in [600, 800]) {
        await (FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope-$w.ttf'))).load();
      }
      final art = await FooterArtwork(files).png();
      final footer = cv.imread(art, flags: cv.IMREAD_UNCHANGED);
      expect(footer.channels, 4);
      final src = cv.imread(page('p'));
      final stamped = pipe.stampFooter(src, footer);
      final path = p.join(tmp.path, 'stamped.jpg');
      pipe.writeJpeg(stamped, path, quality: 90);
      final strip = (2828 * PageFooter.imageStripFraction).round();
      expect(stamped.rows, 2828 + strip);
      expect(stamped.cols, 2000);
      // The page itself is untouched, right to its bottom-right corner.
      expect(stamped.at<cv.Vec3b>(2827, 1999).val1, closeTo(60, 3));
      // The strip is white on the left, the black square on the right.
      final mid = 2828 + strip ~/ 2;
      expect(stamped.at<cv.Vec3b>(mid, 100).val1, greaterThan(240));
      final squareRight = 2000 - (strip * PageFooter.rightMm / PageFooter.bandMm).round();
      final squareLeft = squareRight - footer.cols * strip * 0.6 / footer.rows;
      expect(stamped.at<cv.Vec3b>(mid, (squareLeft + 3).round()).val1, lessThan(40), reason: 'black square');
      for (final m in [footer, src, stamped]) {
        m.dispose();
      }
      return path;
    });
    expect(File(out!).existsSync(), isTrue);
  });

  testWidgets('a PDF page carries the footer and its store link', (tester) async {
    final bytes = await tester.runAsync(() async {
      final pdf = await PdfBuilderImpl(IsolateRunner()).fromPages(
        [page('a', w: 1000, h: 1414)],
        const PdfOptions(footer: true),
        outputPath: p.join(tmp.path, 'out.pdf'),
      );
      return pdf.readAsBytesSync();
    });
    final text = String.fromCharCodes(bytes!);
    expect(text, contains(PageFooter.url));
    expect(text, contains('/FontFile2'), reason: 'Manrope embedded');
  });

  test('the white mark asset parses (no mask) for the PDF badge', () async {
    final svg = File('assets/images/flashdox_mark_white.svg').readAsStringSync();
    expect(svg, isNot(contains('mask')));
    expect(await rootBundle.loadString('assets/images/flashdox_mark_white.svg'), svg);
  });
}
