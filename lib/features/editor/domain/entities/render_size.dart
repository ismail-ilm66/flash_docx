import 'package:flash_dox/core/constants/sizes.dart';

/// Target long-edge size for a render. `full` keeps the original resolution.
enum RenderSize {
  /// Small render for the ID / passport 0° vs 180° check (P0-1).
  probe(640),

  /// The photo given to person segmentation (passport photo backgrounds).
  mask(800),
  thumb(RenderPx.thumbLongEdge),
  preview(RenderPx.previewLongEdge),
  standard(RenderPx.standardExportLongEdge),
  full(null);

  const RenderSize(this.longEdge);

  /// null = original resolution.
  final int? longEdge;
}
