import 'dart:io';
import 'dart:ui' as ui;

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/export/domain/entities/page_footer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// Round 10, P1-6: the footer for JPG / PNG pages, drawn once with the
/// app's own text engine (Manrope SemiBold) and logo, kept as a PNG; the
/// worker scales it into each page (`ImageProcessor.stampFooter`).
@lazySingleton
class FooterArtwork {
  FooterArtwork(this._files);

  final FileStore _files;

  /// Logo height in the artwork, in pixels: big enough to scale down
  /// cleanly to 1.6 % of a 3000 px page.
  static const double logoPx = 64;

  Future<String>? _png;

  /// The artwork's PNG (pill, logo and text, transparent around the pill).
  Future<String> png() => _png ??= _drawOnce();

  Future<String> _drawOnce() async {
    try {
      return await _draw();
    } catch (_) {
      _png = null; // tried again next time
      rethrow;
    }
  }

  Future<String> _draw() async {
    const mm = logoPx / PageFooter.logoMm; // the PDF's proportions
    final svg = await rootBundle.loadString('assets/images/footer_mark.svg');
    final logo = await vg.loadPicture(SvgStringLoader(svg), null);
    final text = TextPainter(
      text: const TextSpan(
        text: PageFooter.text,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w600,
          // 7 pt on a 4 mm logo.
          fontSize: PageFooter.textPt * 25.4 / 72 * mm,
          color: Color(PageFooter.color),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final logoW = logo.size.width / logo.size.height * logoPx;
    const padH = PageFooter.pillPadHMm * mm;
    const padV = PageFooter.pillPadVMm * mm;
    final w = (padH * 2 + logoW + PageFooter.gapMm * mm + text.width).ceil();
    final h = (padV * 2 + (text.height > logoPx ? text.height : logoPx)).ceil();

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), const Radius.circular(PageFooter.pillRadiusMm * mm)),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: PageFooter.pillOpacity),
    );
    canvas
      ..save()
      ..translate(padH, (h - logoPx) / 2)
      ..scale(logoPx / logo.size.height)
      ..drawPicture(logo.picture)
      ..restore();
    text.paint(canvas, Offset(padH + logoW + PageFooter.gapMm * mm, (h - text.height) / 2));
    logo.picture.dispose();
    final image = await rec.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final out = p.join(_files.captureTemp.path, 'footer_${w}x$h.png');
    await File(out).writeAsBytes(bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
    return out;
  }
}
