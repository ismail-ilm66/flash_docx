import 'dart:math' as math;
import 'dart:ui';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Pure geometry for the camera preview well. The well is a 3:4 box; the
/// photo is cover-fitted into it. These helpers map between the box and the
/// photo so the guide frame and tap-to-focus land where the user expects.
abstract final class PreviewGeometry {
  /// Portrait aspect (width / height) of the preview well.
  static const double wellAspect = 3 / 4;

  /// Guide frame as a fraction of the well: centred, 84% of the well width
  /// for landscape shapes, or fitted to 84% of the width / 72% of the height
  /// for portrait shapes. [aspect] is width / height.
  static Rect guideRect(double aspect) {
    const maxW = 0.84;
    const maxH = 0.72;
    // Work in well units where width = 1 and height = 1 / wellAspect.
    const wellH = 1 / wellAspect;
    var w = maxW;
    var h = w / aspect;
    if (h > maxH * wellH) {
      h = maxH * wellH;
      w = h * aspect;
    }
    // Convert back to fractions of each axis.
    final fw = w;
    final fh = h / wellH;
    return Rect.fromLTWH((1 - fw) / 2, (1 - fh) / 2, fw, fh);
  }

  /// Maps a point given as fractions of the well (0..1) to fractions of the
  /// photo (0..1), for a photo of [photoAspect] (width / height) cover-fitted
  /// into the well. Points outside the visible photo are clamped.
  static Offset wellToPhoto(Offset p, {required double photoAspect}) {
    // Scale so the photo covers the well.
    const scaleX = 1.0; // well width = 1
    const wellH = 1 / wellAspect;
    final photoH = 1 / photoAspect; // photo width = 1
    final k = math.max(scaleX, wellH / photoH); // cover
    final shownW = k; // photo width in well units
    final shownH = k * photoH;
    final offX = (1 - shownW) / 2;
    final offY = (wellH - shownH) / 2;
    final x = (p.dx - offX) / shownW;
    final y = (p.dy * wellH - offY) / shownH;
    return Offset(x.clamp(0, 1), y.clamp(0, 1));
  }

  /// The guide frame expressed in photo coordinates, as a [Quad].
  static Quad guideQuad(double aspect, {required double photoAspect}) {
    final r = guideRect(aspect);
    Pt pt(Offset o) {
      final m = wellToPhoto(o, photoAspect: photoAspect);
      return Pt(m.dx, m.dy);
    }
    return Quad(
      tl: pt(r.topLeft),
      tr: pt(r.topRight),
      br: pt(r.bottomRight),
      bl: pt(r.bottomLeft),
    );
  }
}
