import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';

/// Passport photo sizes (feature 5).
class PhotoSize extends Equatable {
  const PhotoSize(this.widthMm, this.heightMm);

  /// Pakistan / UK / EU passport photo.
  static const passport = PhotoSize(35, 45);

  /// US passport / visa photo.
  static const twoByTwo = PhotoSize(50.8, 50.8);

  final double widthMm;
  final double heightMm;

  double get aspect => widthMm / heightMm;

  @override
  List<Object?> get props => [widthMm, heightMm];
}

/// Where the photo sits under the fixed crop frame: its top-left and scale
/// in screen pixels. Pure maths for the crop screen.
class PhotoPlacement {
  const PhotoPlacement(this.offset, this.scale);

  final Offset offset;

  /// Screen pixels per image pixel.
  final double scale;

  /// The smallest scale that still covers [frame], centred on it.
  factory PhotoPlacement.cover(Size image, Rect frame) {
    final s = math.max(frame.width / image.width, frame.height / image.height);
    return PhotoPlacement(
      Offset(
        frame.center.dx - image.width * s / 2,
        frame.center.dy - image.height * s / 2,
      ),
      s,
    );
  }

  /// Keeps the frame covered: never smaller than `cover`, never more than
  /// `maxZoom` × that, and never panned past an edge.
  PhotoPlacement clamp(Size image, Rect frame, {double maxZoom = 6}) {
    final minS = math.max(
      frame.width / image.width,
      frame.height / image.height,
    );
    final s = scale.clamp(minS, minS * maxZoom);
    final w = image.width * s;
    final h = image.height * s;
    final x = offset.dx.clamp(frame.right - w, frame.left);
    final y = offset.dy.clamp(frame.bottom - h, frame.top);
    return PhotoPlacement(Offset(x, y), s);
  }

  /// Zooms by [factor] about [focal] (screen point), then pans by [pan].
  PhotoPlacement transformed({
    required double factor,
    required Offset focal,
    Offset pan = Offset.zero,
  }) {
    final s = scale * factor;
    final o = focal - (focal - offset) * factor + pan;
    return PhotoPlacement(o, s);
  }

  /// The framed part of the photo as a crop quad (fractions of the image).
  Quad cropFor(Size image, Rect frame) {
    double fx(double x) =>
        ((x - offset.dx) / (image.width * scale)).clamp(0, 1);
    double fy(double y) =>
        ((y - offset.dy) / (image.height * scale)).clamp(0, 1);
    final l = fx(frame.left);
    final r = fx(frame.right);
    final t = fy(frame.top);
    final b = fy(frame.bottom);
    return Quad(tl: Pt(l, t), tr: Pt(r, t), br: Pt(r, b), bl: Pt(l, b));
  }

  /// The inverse of [cropFor]: where to put the photo so [crop] fills
  /// [frame] (re-cropping a saved photo).
  factory PhotoPlacement.fromCrop(Quad crop, Size image, Rect frame) {
    final s = frame.width / ((crop.tr.x - crop.tl.x) * image.width);
    return PhotoPlacement(
      Offset(
        frame.left - crop.tl.x * image.width * s,
        frame.top - crop.tl.y * image.height * s,
      ),
      s,
    );
  }
}
