import 'dart:math' as math;
import 'dart:ui';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

/// Pure geometry for the camera preview.
///
/// Round 4 cover-fitted the photo to the whole screen, which cut its sides
/// off: pages looked further away than they were, and users stepped back
/// (round 7, P0-2). The preview is now shown whole in a box of the photo's
/// shape ([CameraLayout]), so with the box as the viewport these helpers
/// map screen fractions to the same photo fractions. They still handle a
/// viewport of another shape (cover fit) for safety.
abstract final class PreviewGeometry {
  /// Portrait aspect (width / height) of a capture until the camera reports
  /// its own.
  static const double defaultPhotoAspect = 3 / 4;

  /// The guide frame as fractions of the [viewport]: a constant shape on
  /// screen (P1-4), 84 % of the width, or 72 % of the height of [area] if
  /// that is smaller, centred in [area] (fractions of the viewport — the
  /// part between the top bar and the controls). [aspect] is width / height.
  static Rect guideRect(double aspect, {required Size viewport, Rect area = const Rect.fromLTWH(0, 0, 1, 1)}) {
    final vw = viewport.width;
    final vh = viewport.height;
    final a = Rect.fromLTWH(area.left * vw, area.top * vh, area.width * vw, area.height * vh);
    var w = 0.84 * vw;
    var h = w / aspect;
    if (h > 0.72 * a.height) {
      h = 0.72 * a.height;
      w = h * aspect;
    }
    final c = a.center;
    return Rect.fromLTWH((c.dx - w / 2) / vw, (c.dy - h / 2) / vh, w / vw, h / vh);
  }

  /// Maps a point given as fractions of the [viewport] to fractions of the
  /// photo (0..1) for a photo of [photoAspect] (portrait width / height)
  /// cover-fitted to the viewport. Points outside the photo are clamped.
  static Offset viewportToPhoto(Offset p, {required double photoAspect, required Size viewport}) {
    final vw = viewport.width;
    final vh = viewport.height;
    // Photo of width photoAspect, height 1, scaled by k to cover.
    final k = math.max(vw / photoAspect, vh);
    final shownW = photoAspect * k;
    final shownH = k;
    final offX = (vw - shownW) / 2;
    final offY = (vh - shownH) / 2;
    final x = (p.dx * vw - offX) / shownW;
    final y = (p.dy * vh - offY) / shownH;
    return Offset(x.clamp(0, 1), y.clamp(0, 1));
  }

  /// The guide frame in photo coordinates, as a [Quad].
  static Quad guideQuad(
    double aspect, {
    required double photoAspect,
    required Size viewport,
    Rect area = const Rect.fromLTWH(0, 0, 1, 1),
  }) {
    final r = guideRect(aspect, viewport: viewport, area: area);
    Pt pt(Offset o) {
      final m = viewportToPhoto(o, photoAspect: photoAspect, viewport: viewport);
      return Pt(m.dx, m.dy);
    }

    return Quad(tl: pt(r.topLeft), tr: pt(r.topRight), br: pt(r.bottomRight), bl: pt(r.bottomLeft));
  }
}

/// Round 7, P0-2: what you see is what you get. The preview is shown whole
/// (no cover crop) in a box of the photo's own aspect, top-aligned under
/// the status bar, as wide as the screen unless the shutter row below
/// wouldn't fit. The top bar, mode pills and hint sit over the box.
class CameraLayout {
  const CameraLayout._(this.box, this.guideArea);

  /// Builds the layout for a [screen] with system [padding] and a photo of
  /// [photoAspect] (portrait width / height). [modes]: the mode pills are
  /// shown over the bottom of the box.
  factory CameraLayout.of(Size screen, EdgeInsets padding, double photoAspect, {required bool modes}) {
    final top = padding.top;
    final maxH = screen.height - top - controlsHeight - padding.bottom;
    var w = screen.width;
    var h = w / photoAspect;
    if (h > maxH && maxH > 0) {
      h = maxH;
      w = h * photoAspect;
    }
    final box = Rect.fromLTWH((screen.width - w) / 2, top, w, h);
    final below = bottomOverlay(modes: modes);
    final guideTop = math.min(topBar / h, 0.4);
    final guideBottom = math.max((h - below) / h, 0.6);
    return CameraLayout._(box, Rect.fromLTRB(0, guideTop, 1, guideBottom));
  }

  /// ✕ · title · flash, over the top of the box.
  static const double topBar = 70;

  /// The shutter row (80) and its margins, below the box.
  static const double controlsHeight = 80 + 2 * 14;

  static const double modePills = 36;
  static const double hintChip = 40;
  static const double gap = 10;

  /// How much of the box bottom the pills and the hint cover.
  static double bottomOverlay({required bool modes}) => (modes ? modePills + gap : 0) + hintChip + gap;

  /// The preview box, in screen pixels. The photo is exactly what's in it.
  final Rect box;

  /// Where the ID / passport frame is centred: the part of the box between
  /// the top bar and the pills, as fractions of the box.
  final Rect guideArea;
}
