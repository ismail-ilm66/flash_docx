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

  static const double _handleRadius = 14;
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
                _Magnifier(focal: _touch!, box: box),
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

class _Magnifier extends StatelessWidget {
  const _Magnifier({required this.focal, required this.box});
  final Offset focal;
  final Size box;

  static const double _size = 110;
  static const double _lift = 90;

  @override
  Widget build(BuildContext context) {
    // Place the loupe above the finger, flipping below when near the top.
    var center = focal - const Offset(0, _lift);
    if (center.dy - _size / 2 < 0) center = focal + const Offset(0, _lift);
    center = Offset(center.dx.clamp(_size / 2, box.width - _size / 2), center.dy);
    return Positioned(
      left: center.dx - _size / 2,
      top: center.dy - _size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size(_size, _size),
          magnificationScale: 2.2,
          focalPointOffset: focal - center,
          decoration: MagnifierDecoration(
            shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 2)),
            shadows: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: const Center(child: Icon(Icons.add, size: 18, color: Colors.white70)),
        ),
      ),
    );
  }
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
    // Dim outside the quad.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addPath(path, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Edge midpoints as subtle hints.
    for (var i = 0; i < 4; i++) {
      final mid = (points[i] + points[(i + 1) % 4]) / 2;
      canvas.drawCircle(mid, 4, Paint()..color = accent.withValues(alpha: 0.6));
    }
    for (var i = 0; i < 4; i++) {
      final isActive = active == i;
      canvas.drawCircle(points[i], handleRadius + (isActive ? 4 : 0), Paint()..color = accent.withValues(alpha: 0.25));
      canvas.drawCircle(points[i], isActive ? 9 : 7, Paint()..color = Colors.white);
      canvas.drawCircle(
        points[i],
        isActive ? 9 : 7,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) =>
      old.points != points || old.active != active || old.accent != accent;
}
