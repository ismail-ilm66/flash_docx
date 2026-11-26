/// Round 11, section F (Reduce size): what the user asks for.
library;

import 'package:flutter/foundation.dart';

/// The picture format of reduced images.
enum ReduceFormat { jpg, png, webp }

extension ReduceFormatX on ReduceFormat {
  String get extension => switch (this) {
    ReduceFormat.jpg => 'jpg',
    ReduceFormat.png => 'png',
    ReduceFormat.webp => 'webp',
  };
}

/// The pixel size of reduced images: the original, a box ([exact]: exactly
/// that size, the centre kept; else fitted inside it), or a long side.
@immutable
class PixelSize {
  const PixelSize.original() : width = null, height = null, longSide = null, exact = false;
  const PixelSize.box(int this.width, int this.height, {this.exact = true}) : longSide = null;
  const PixelSize.longSide(int this.longSide) : width = null, height = null, exact = false;

  final int? width;
  final int? height;
  final int? longSide;

  /// Cropped to exactly [width] × [height] (a form's upload size); else
  /// fitted inside, keeping the shape.
  final bool exact;

  bool get isOriginal => width == null && longSide == null;

  /// The search may make the picture smaller than asked (never for an
  /// exact size: a form wants exactly that).
  bool get canShrink => !exact;

  /// Presets: Original · 300×300 · 600×600 · 1080 px · 1600 px long side.
  static const presets = [
    PixelSize.original(),
    PixelSize.box(300, 300),
    PixelSize.box(600, 600),
    PixelSize.longSide(1080),
    PixelSize.longSide(1600),
  ];

  @override
  bool operator ==(Object other) =>
      other is PixelSize && other.width == width && other.height == height && other.longSide == longSide && other.exact == exact;

  @override
  int get hashCode => Object.hash(width, height, longSide, exact);
}

/// Max file size presets: 50 KB · 100 KB · 200 KB · 500 KB · 1 MB.
const List<int> reduceSizePresets = [50 * 1000, 100 * 1000, 200 * 1000, 500 * 1000, 1000 * 1000];

/// What a reduce gave: the files, their size before and after, and whether
/// the target was reached (else [files] are the smallest possible).
class ReduceResult {
  const ReduceResult({
    required this.files,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.fits,
    required this.count,
  });

  final List<String> files;
  final int bytesBefore;
  final int bytesAfter;
  final bool fits;

  /// Pages or images.
  final int count;
}
