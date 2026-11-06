import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/preview_geometry.dart';
import 'package:flutter/material.dart';

/// The full-screen camera viewport (round 4, P1-2): camera feed (cover
/// fit), guide frame, tap-to-focus ring, the white capture flash and the
/// page that flies into the stack.
class CameraViewport extends StatefulWidget {
  const CameraViewport({
    required this.preview,
    super.key,
    this.guideAspect,
    this.guideArea = const Rect.fromLTWH(0, 0, 1, 1),
    this.focusPoint,
    this.flashTick = 0,
    this.onTap,
    this.stackKey,
    this.flyTick = 0,
  });

  final Widget preview;

  /// Frame shape (width / height), or null for no frame (Document mode).
  final double? guideAspect;

  /// Where the frame is centred: the visible part between the top bar and
  /// the controls, as fractions of the viewport.
  final Rect guideArea;
  final Offset? focusPoint;
  final int flashTick;
  final ValueChanged<Offset>? onTap;
  final GlobalKey? stackKey;

  /// Increment to fly a page into the stack.
  final int flyTick;

  @override
  State<CameraViewport> createState() => _CameraViewportState();
}

class _CameraViewportState extends State<CameraViewport> with TickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Offset? _flyTarget; // in well-local coordinates
  bool _flying = false;

  @override
  void didUpdateWidget(CameraViewport old) {
    super.didUpdateWidget(old);
    if (widget.flashTick != old.flashTick) {
      _flash
        ..value = 1
        ..reverse();
    }
    if (widget.flyTick != old.flyTick) _startFly();
  }

  void _startFly() {
    final stackCtx = widget.stackKey?.currentContext;
    final box = context.findRenderObject();
    if (stackCtx == null || box is! RenderBox) return;
    final stackBox = stackCtx.findRenderObject();
    if (stackBox is! RenderBox) return;
    final target = box.globalToLocal(stackBox.localToGlobal(stackBox.size.center(Offset.zero)));
    setState(() {
      _flying = true;
      _flyTarget = target;
    });
    _fly
      ..reset()
      ..forward().whenComplete(() {
        if (mounted) setState(() => _flying = false);
      });
  }

  @override
  void dispose() {
    _flash.dispose();
    _fly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.guideAspect;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = aspect == null ? null : PreviewGeometry.guideRect(aspect, viewport: size, area: widget.guideArea);
        final frame = rect == null
            ? null
            : Rect.fromLTWH(
                rect.left * size.width,
                rect.top * size.height,
                rect.width * size.width,
                rect.height * size.height,
              );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onTap == null
              ? null
              : (d) => widget.onTap!(
                    Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height),
                  ),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.preview,
                if (frame != null) CustomPaint(painter: _CornerFramePainter(frame)),
                if (widget.focusPoint != null)
                  Positioned(
                    left: widget.focusPoint!.dx * size.width - 32,
                    top: widget.focusPoint!.dy * size.height - 32,
                    child: const _FocusRing(key: ValueKey('focus')),
                  ),
                FadeTransition(
                  opacity: _flash,
                  child: const ColoredBox(color: Colors.white),
                ),
                if (_flying && _flyTarget != null)
                  AnimatedBuilder(
                    animation: _fly,
                    builder: (context, child) {
                      final t = Curves.easeInCubic.transform(_fly.value);
                      final start = size.center(Offset.zero);
                      final pos = Offset.lerp(start, _flyTarget, t)!;
                      final scale = 1 - 0.8 * t;
                      return Positioned(
                        left: pos.dx - size.width * 0.25 * scale,
                        top: pos.dy - size.height * 0.25 * scale,
                        width: size.width * 0.5 * scale,
                        height: size.height * 0.5 * scale,
                        child: Opacity(opacity: 1 - 0.3 * t, child: child),
                      );
                    },
                    // A plain page card: decoding the 12–16 MP shot here
                    // would cost the UI on low-end phones (P0-C).
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: Radii.smR,
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FocusRing extends StatefulWidget {
  const _FocusRing({super.key});

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutBack.transform(_c.value);
        return Transform.scale(
          scale: 1.4 - 0.4 * t,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFC233), width: 2),
            ),
            child: const Center(
              child: SizedBox(
                width: 8,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFC233)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  const _CornerFramePainter(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 34.0;
    const r = 6.0;
    final l = frame.left;
    final t = frame.top;
    final w = frame.right;
    final h = frame.bottom;
    final corners = [
      (Offset(l, t + len), Offset(l, t + r), Offset(l + r, t), Offset(l + len, t)),
      (Offset(w - len, t), Offset(w - r, t), Offset(w, t + r), Offset(w, t + len)),
      (Offset(w, h - len), Offset(w, h - r), Offset(w - r, h), Offset(w - len, h)),
      (Offset(l + len, h), Offset(l + r, h), Offset(l, h - r), Offset(l, h - len)),
    ];
    for (final (a, b, cc, d) in corners) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..arcToPoint(cc, radius: const Radius.circular(r))
        ..lineTo(d.dx, d.dy);
      canvas.drawPath(path, paint);
    }
    // Dim outside the frame a little so it reads as the target.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(r)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(covariant _CornerFramePainter old) => old.frame != frame;
}
