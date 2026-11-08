import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flash_dox/features/signature/domain/catmull_rom.dart';
import 'package:flutter/material.dart';

/// Strokes drawn on a [DrawPad], with undo.
class DrawPadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.isEmpty;

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    final s = _strokes.last;
    // Skip jitter under a pixel.
    if ((s.last - p).distance < 1) return;
    s.add(p);
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Replaces the strokes with [strokes] (drawn on a bigger canvas) scaled
  /// down to fit [size] with [padding], centred (P1-5 Expand). Smaller
  /// drawings keep their size.
  void replaceWith(List<List<Offset>> strokes, Size size, {double padding = 16}) {
    _strokes.clear();
    final pts = strokes.expand((s) => s).toList();
    if (pts.isNotEmpty) {
      var bounds = Rect.fromPoints(pts.first, pts.first);
      for (final p in pts) {
        bounds = bounds.expandToInclude(Rect.fromCenter(center: p, width: 0, height: 0));
      }
      final room = Size(math.max(1, size.width - 2 * padding), math.max(1, size.height - 2 * padding));
      final k = math.min(1.0, math.min(room.width / math.max(1, bounds.width), room.height / math.max(1, bounds.height)));
      final centre = size.center(Offset.zero);
      for (final s in strokes) {
        _strokes.add([for (final p in s) centre + (p - bounds.center) * k]);
      }
    }
    notifyListeners();
  }

  /// Black strokes on transparent, trimmed to the ink, at [scale]× for a
  /// sharp print. Ink colour is applied when the signature is placed.
  Future<ui.Image?> toImage({double strokeWidth = DrawPad.strokeWidth, double scale = 3}) async {
    final pts = _strokes.expand((s) => s).toList();
    if (pts.isEmpty) return null;
    final pad = strokeWidth * 2;
    var bounds = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      bounds = bounds.expandToInclude(Rect.fromCenter(center: p, width: 0, height: 0));
    }
    bounds = bounds.inflate(pad);
    final w = math.max(1, (bounds.width * scale).ceil());
    final h = math.max(1, (bounds.height * scale).ceil());
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    _paintStrokes(canvas, _strokes, Colors.black, strokeWidth);
    return rec.endRecording().toImage(w, h);
  }
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color, double width) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, width / 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }
    final smooth = catmullRom(s);
    final path = Path()..moveTo(smooth.first.dx, smooth.first.dy);
    for (final p in smooth.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// "Draw" (feature 4): sign with a finger; strokes are smoothed with a
/// Catmull-Rom spline.
class DrawPad extends StatelessWidget {
  const DrawPad({required this.controller, required this.ink, super.key});

  static const strokeWidth = 3.5;

  final DrawPadController controller;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => controller._start(d.localPosition),
      onPanUpdate: (d) => controller._extend(d.localPosition),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => CustomPaint(
          painter: _StrokesPainter(controller.strokes, ink),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes, this.ink);
  final List<List<Offset>> strokes;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, strokes, ink, DrawPad.strokeWidth);

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}
