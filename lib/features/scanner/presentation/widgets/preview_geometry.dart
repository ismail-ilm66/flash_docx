import 'dart:math' as math;
import 'dart:ui';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Pure geometry for the full-screen camera preview (round 4, P1-2).
///
/// The photo (4:3 sensor, shown portrait as 3:4) is cover-fitted to the
/// whole screen, so on tall phones its sides run off the screen. These
/// helpers map between screen fractions and photo fractions through that
/// cover crop, so the guide frame and tap-to-focus land where the user sees
/// them.
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
