import 'package:flash_dox/core/constants/sizes.dart';

/// Target long-edge size for a render. `full` keeps the original resolution.
enum RenderSize {
  thumb(RenderPx.thumbLongEdge),
  preview(RenderPx.previewLongEdge),
  standard(RenderPx.standardExportLongEdge),
  full(null);

  const RenderSize(this.longEdge);

  /// null = original resolution.
  final int? longEdge;
}
