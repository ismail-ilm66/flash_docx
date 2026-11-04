import 'dart:io';
import 'dart:ui' as ui;

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter/material.dart';

/// Shows an image with four draggable corners and a magnifier while dragging.
/// Works in the image's own coordinate space; wrap it in a `RotatedBox` to
/// show rotation without changing the quad maths.
class QuadEditor extends StatefulWidget {
  const QuadEditor({
    required this.imagePath,
    required this.quad,
    required this.onCornerMoved,
    required this.onDragEnd,
    super.key,
    this.accent = const Color(0xFFFFC233),
  });

  final String imagePath;
  final Quad quad;
  final void Function(int corner, Pt point) onCornerMoved;
  final VoidCallback onDragEnd;
  final Color accent;

  @override
  State<QuadEditor> createState() => _QuadEditorState();
}

class _QuadEditorState extends State<QuadEditor> {
  ui.Image? _image;
  int? _active;
  Offset? _touch;

  static const double _handleRadius = 12;
  static const double _hitRadius = 36;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QuadEditor old) {
    super.didUpdateWidget(old);
    if (old.imagePath != widget.imagePath) _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) return;
    setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect _fit(Size box, ui.Image img) {
    final ia = img.width / img.height;
    final ba = box.width / box.height;
    double w;
    double h;
    if (ia > ba) {
      w = box.width;
      h = w / ia;
    } else {
      h = box.height;
      w = h * ia;
    }
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset _toScreen(Pt p, Rect r) => Offset(r.left + p.x * r.width, r.top + p.y * r.height);
  Pt _toNorm(Offset o, Rect r) =>
      Pt(((o.dx - r.left) / r.width).clamp(0, 1), ((o.dy - r.top) / r.height).clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = _fit(box, img);
        final pts = widget.quad.points.map((p) => _toScreen(p, rect)).toList();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            var best = -1;
            var bestD = _hitRadius;
            for (var i = 0; i < 4; i++) {
              final dist = (pts[i] - d.localPosition).distance;
              if (dist < bestD) {
                bestD = dist;
                best = i;
              }
            }
            if (best >= 0) setState(() { _active = best; _touch = d.localPosition; });
          },
          onPanUpdate: (d) {
            final a = _active;
            if (a == null) return;
            setState(() => _touch = d.localPosition);
            widget.onCornerMoved(a, _toNorm(d.localPosition, rect));
          },
          onPanEnd: (_) => _endDrag(),
          onPanCancel: _endDrag,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: rect,
                child: RawImage(image: img, fit: BoxFit.fill),
              ),
              CustomPaint(
                painter: _QuadPainter(
                  points: pts,
                  active: _active,
                  accent: widget.accent,
                  handleRadius: _handleRadius,
                ),
              ),
              if (_active != null && _touch != null)
                _Loupe(
                  image: img,
                  imageRect: rect,
                  corner: pts[_active!],
                  prev: pts[(_active! + 3) % 4],
                  next: pts[(_active! + 1) % 4],
                  touch: _touch!,
                  box: box,
                  accent: widget.accent,
                ),
            ],
          ),
        );
      },
    );
  }

  void _endDrag() {
    if (_active == null) return;
    setState(() { _active = null; _touch = null; });
    widget.onDragEnd();
  }
}

/// Corner loupe: 2.5× of the undimmed image around the dragged corner,
/// with a crosshair and the two crop edges that meet there. Sits in the
/// top-left of the image area, or the top-right when the finger is in the
/// top-left quarter, so it is never under the finger.
class _Loupe extends StatelessWidget {
  const _Loupe({
    required this.image,
    required this.imageRect,
    required this.corner,
    required this.prev,
    required this.next,
    required this.touch,
    required this.box,
    required this.accent,
  });

  final ui.Image image;
  final Rect imageRect;
  final Offset corner;
  final Offset prev;
  final Offset next;
  final Offset touch;
  final Size box;
  final Color accent;

  static const double size = 110;
  static const double _margin = 12;

  @override
  Widget build(BuildContext context) {
    final fingerTopLeft = touch.dx < box.width / 2 && touch.dy < box.height / 2;
    final left = fingerTopLeft ? box.width - size - _margin : _margin;
    return Positioned(
      left: left.clamp(0, box.width - size),
      top: _margin,
      width: size,
      height: size,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: CustomPaint(
            painter: _LoupePainter(
              image: image,
              imageRect: imageRect,
              corner: corner,
              prev: prev,
              next: next,
              accent: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  _LoupePainter({
    required this.image,
    required this.imageRect,
    required this.corner,
    required this.prev,
    required this.next,
    required this.accent,
  });

  final ui.Image image;
  final Rect imageRect;
  final Offset corner;
  final Offset prev;
  final Offset next;
  final Color accent;

  static const double zoom = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    Offset toLoupe(Offset p) => c + (p - corner) * zoom;

    canvas
      ..save()
      ..clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)))
      ..drawColor(const Color(0xFF000000), BlendMode.src);
    // The image itself, at full brightness.
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(zoom)
      ..translate(-corner.dx, -corner.dy)
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        imageRect,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
    // The two crop edges meeting at this corner.
    final edge = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(c, toLoupe(prev), edge)
      ..drawLine(c, toLoupe(next), edge);
    // Crosshair: white with a dark outline so it reads on any background.
    const arm = 12.0;
    final outline = Paint()
      ..color = const Color(0xB3000000)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final cross = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final p in [outline, cross]) {
      canvas
        ..drawLine(c - const Offset(arm, 0), c + const Offset(arm, 0), p)
        ..drawLine(c - const Offset(0, arm), c + const Offset(0, arm), p);
    }
    canvas.restore();
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _LoupePainter old) =>
      old.corner != corner || old.prev != prev || old.next != next || old.image != image || old.imageRect != imageRect;
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.points,
    required this.active,
    required this.accent,
    required this.handleRadius,
  });

  final List<Offset> points;
  final int? active;
  final Color accent;
  final double handleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final white = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke;
    // Edge midpoints: small pills laid along each edge.
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      final mid = (a + b) / 2;
      final angle = (b - a).direction;
      canvas
        ..save()
        ..translate(mid.dx, mid.dy)
        ..rotate(angle);
      final pill = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 30, height: 10),
        const Radius.circular(5),
      );
      canvas
        ..drawRRect(pill, white)
        ..drawRRect(pill.deflate(1), ring..strokeWidth = 2)
        ..restore();
    }
    // Corners: white discs with an accent ring. The one being dragged
    // fades to 30% so it doesn't hide the point under the finger.
    for (var i = 0; i < 4; i++) {
      final dragging = active == i;
      final a = dragging ? 0.3 : 1.0;
      canvas
        ..drawCircle(points[i], handleRadius, Paint()..color = Colors.white.withValues(alpha: a))
        ..drawCircle(
          points[i],
          handleRadius - 1.5,
          Paint()
            ..color = accent.withValues(alpha: a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) =>
      old.points != points || old.active != active || old.accent != accent;
}
