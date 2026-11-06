import 'package:flutter/material.dart';

/// Drives the zoom of the current page from outside (the − / 100 % / +
/// pill on Enhance).
class ZoomController extends ChangeNotifier {
  _ZoomablePagesState? _state;
  double _scale = 1;

  /// Zoom of the current page (1 = fit).
  double get scale => _scale;

  void zoomIn() => _state?._zoomBy(1.5);
  void zoomOut() => _state?._zoomBy(1 / 1.5);
  void reset() => _state?._animateTo(Matrix4.identity());

  void _update(double s) {
    if ((s - _scale).abs() < 0.001) return;
    _scale = s;
    notifyListeners();
  }
}

/// Swipeable pages that can be zoomed (round 4, P0-5).
///
/// * At 1× a horizontal swipe changes page; zoomed in, the page view stops
///   scrolling so pinch and pan never fight the swipe.
/// * Double-tap toggles 1× ↔ 2.5× at the tap point; pinch 1×–5×.
/// * Each page's zoom area fills the page, so every corner can be reached and
///   content is clipped only by the viewport.
/// * Changing page resets the zoom.
class ZoomablePages extends StatefulWidget {
  const ZoomablePages({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
    this.controller,
    this.zoom,
    this.onPageChanged,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final PageController? controller;
  final ZoomController? zoom;
  final ValueChanged<int>? onPageChanged;

  static const double maxScale = 5;
  static const double doubleTapScale = 2.5;

  @override
  State<ZoomablePages> createState() => _ZoomablePagesState();
}

class _ZoomablePagesState extends State<ZoomablePages> with SingleTickerProviderStateMixin {
  late final PageController _pages = widget.controller ?? PageController();
  final Map<int, TransformationController> _transforms = {};
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _tween;
  int _current = 0;
  bool _zoomed = false;
  Offset? _doubleTapAt;
  Size _viewport = Size.zero;

  TransformationController _tc(int i) => _transforms.putIfAbsent(i, () {
        final c = TransformationController();
        c.addListener(() {
          if (i == _current) _onTransform(c.value);
        });
        return c;
      });

  @override
  void initState() {
    super.initState();
    widget.zoom?._state = this;
    _anim.addListener(() {
      final t = _tween;
      if (t != null) _tc(_current).value = t.value;
    });
  }

  @override
  void didUpdateWidget(ZoomablePages old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      old.zoom?._state = null;
      widget.zoom?._state = this;
    }
  }

  @override
  void dispose() {
    widget.zoom?._state = null;
    _anim.dispose();
    for (final c in _transforms.values) {
      c.dispose();
    }
    if (widget.controller == null) _pages.dispose();
    super.dispose();
  }

  void _onTransform(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    widget.zoom?._update(s);
    final zoomed = s > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _onPage(int i) {
    // Reset the page we left, then follow the new one.
    _tc(_current).value = Matrix4.identity();
    _current = i;
    _onTransform(_tc(i).value);
    widget.onPageChanged?.call(i);
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(begin: _tc(_current).value, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim
      ..value = 0
      ..forward();
  }

  /// Zoom around the viewport centre by [factor], within 1×–5×.
  void _zoomBy(double factor) {
    final m = _tc(_current).value;
    final s = m.getMaxScaleOnAxis();
    final target = (s * factor).clamp(1.0, ZoomablePages.maxScale);
    if (target <= 1.001) {
      _animateTo(Matrix4.identity());
      return;
    }
    _animateTo(_zoomAround(_viewport.center(Offset.zero), target, from: m));
  }

  /// A matrix that shows [scale]× with the scene point under [focal] (in
  /// viewport coordinates) staying put.
  Matrix4 _zoomAround(Offset focal, double scale, {Matrix4? from}) {
    final current = from ?? _tc(_current).value;
    final inv = Matrix4.inverted(current);
    final scene = MatrixUtils.transformPoint(inv, focal);
    final m = Matrix4.identity()
      ..translateByDouble(focal.dx - scene.dx * scale, focal.dy - scene.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    return _clamp(m, scale);
  }

  /// Keeps the zoomed page covering the viewport (no empty margins).
  Matrix4 _clamp(Matrix4 m, double scale) {
    final w = _viewport.width;
    final h = _viewport.height;
    final tx = m.getTranslation().x.clamp(w - w * scale, 0.0);
    final ty = m.getTranslation().y.clamp(h - h * scale, 0.0);
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _onDoubleTap() {
    final at = _doubleTapAt ?? _viewport.center(Offset.zero);
    final s = _tc(_current).value.getMaxScaleOnAxis();
    _animateTo(s > 1.01 ? Matrix4.identity() : _zoomAround(at, ZoomablePages.doubleTapScale, from: Matrix4.identity()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        return PageView.builder(
          controller: _pages,
          itemCount: widget.itemCount,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          onPageChanged: _onPage,
          itemBuilder: (context, i) => GestureDetector(
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: _onDoubleTap,
            child: InteractiveViewer(
              key: ValueKey('zoom-$i'),
              transformationController: _tc(i),
              maxScale: ZoomablePages.maxScale,
              // Only pan when zoomed, so a 1× swipe goes to the PageView.
              panEnabled: _zoomed && i == _current,
              child: SizedBox.fromSize(
                size: constraints.biggest,
                child: widget.itemBuilder(context, i),
              ),
            ),
          ),
        );
      },
    );
  }
}
