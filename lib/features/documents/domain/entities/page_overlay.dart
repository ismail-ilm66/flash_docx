import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_overlay.freezed.dart';
part 'page_overlay.g.dart';

enum OverlayKind { signature, date }

/// Ink for a placed signature or date. Original keeps the scanned colours.
enum InkColor { black, blue, original }

/// A signature or date stamp placed on a page (feature 4). Stored in
/// `PageEdits.overlays`, so the original photo is never touched; it's
/// composited as the last render step (export and the viewer's preview).
///
/// The image is a transparent PNG inside the document's folder; the rect is
/// in fractions of the rendered page (after crop and rotation).
@freezed
abstract class PageOverlay with _$PageOverlay {
  const factory PageOverlay({
    required String id,
    required OverlayKind kind,
    required String imagePath,
    required double left,
    required double top,
    required double width,
    required double height,
    @Default(InkColor.blue) InkColor ink,
  }) = _PageOverlay;

  factory PageOverlay.fromJson(Map<String, dynamic> json) => _$PageOverlayFromJson(json);
}
