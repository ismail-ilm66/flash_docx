import 'dart:io';
import 'dart:ui' as ui;

import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/features/export/domain/entities/page_footer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

/// The footer badge for JPG / PNG pages (round 11 style): the black
/// rounded square with the white mark and "Flash Dox: Document Scanner",
/// drawn once with the app's own text engine (Manrope) and kept as a PNG
/// (transparent around it); the worker scales it into the white strip under
/// each page (`ImageProcessor.stampFooter`).
@lazySingleton
class FooterArtwork {
  FooterArtwork(this._files);

  final FileStore _files;

  /// Pixels per millimetre of the artwork: big enough to scale down cleanly
  /// into a 3000 px page's strip.
  static const double pxPerMm = 16;

  Future<String>? _png;

  /// The artwork's PNG; its height is the square's.
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
    const mm = pxPerMm;
    final svg = await rootBundle.loadString('assets/images/flashdox_mark_white.svg');
    final mark = await vg.loadPicture(SvgStringLoader(svg), null);
    const style = TextStyle(
      fontFamily: 'Manrope',
      fontSize: PageFooter.textPt * 25.4 / 72 * mm,
      color: Color(PageFooter.textColor),
    );
    final text = TextPainter(
      text: const TextSpan(
        style: style,
        children: [
          TextSpan(text: PageFooter.brand, style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: PageFooter.tagline, style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const square = PageFooter.squareMm * mm;
    final w = (square + PageFooter.gapMm * mm + text.width).ceil();
    final h = (text.height > square ? text.height : square).ceil();

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final top = (h - square) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, top, square, square), const Radius.circular(PageFooter.squareRadiusMm * mm)),
      Paint()..color = const Color(PageFooter.squareColor),
    );
    const markW = PageFooter.markMm * mm;
    final markH = mark.size.height / mark.size.width * markW;
    canvas
      ..save()
      ..translate((square - markW) / 2, top + (square - markH) / 2)
      ..scale(markW / mark.size.width)
      ..drawPicture(mark.picture)
      ..restore();
    text.paint(canvas, Offset(square + PageFooter.gapMm * mm, (h - text.height) / 2));
    mark.picture.dispose();
    final image = await rec.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final out = p.join(_files.captureTemp.path, 'footer_badge_${w}x$h.png');
    await File(out).writeAsBytes(bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
    return out;
  }
}
