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

  testWidgets('a JPG page gets the footer bottom-right at 1.6 % of its height, on a white pill', (tester) async {
    final out = await tester.runAsync(() async {
      // The app's font, as on the phone (tests default to Ahem boxes).
      await (FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope-600.ttf'))).load();
      final art = await FooterArtwork(files).png();
      final footer = cv.imread(art, flags: cv.IMREAD_UNCHANGED);
      expect(footer.channels, 4);
      final src = cv.imread(page('p'));
      final stamped = pipe.stampFooter(src, footer, artLogoPx: FooterArtwork.logoPx, left: false);
      final path = p.join(tmp.path, 'stamped.jpg');
      pipe.writeJpeg(stamped, path, quality: 90);
      // The pill: near white, bottom-right; the rest untouched.
      const logo = 2828 * PageFooter.imageLogoFraction;
      final y = (2828 - 1.5 * logo - logo / 2).round();
      final pill = stamped.at<cv.Vec3b>(y, (2000 - 1.5 * logo - 10).round());
      expect(pill.val1, greaterThan(200));
      expect(stamped.at<cv.Vec3b>(y, 100).val1, 60, reason: 'left side untouched');
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
        const PdfOptions(footer: true, footerLeft: [false]),
        outputPath: p.join(tmp.path, 'out.pdf'),
      );
      return pdf.readAsBytesSync();
    });
    final text = String.fromCharCodes(bytes!);
    expect(text, contains(PageFooter.url));
    expect(text, contains('/FontFile2'), reason: 'Manrope embedded');
  });

  test('the logo asset parses (no mask)', () async {
    final svg = File('assets/images/footer_mark.svg').readAsStringSync();
    expect(svg, isNot(contains('mask')));
    expect(await rootBundle.loadString('assets/images/footer_mark.svg'), svg);
  });
}
