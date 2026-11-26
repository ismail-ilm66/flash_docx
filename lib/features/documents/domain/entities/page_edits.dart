import 'package:flash_dox/features/documents/domain/entities/enums.dart';
import 'package:flash_dox/features/documents/domain/entities/page_overlay.dart';
import 'package:flash_dox/features/documents/domain/entities/quad.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_edits.freezed.dart';
part 'page_edits.g.dart';

/// Non-destructive edit settings for one page. The original photo is never
/// modified; the processed image is a cache derived from these values.
@freezed
abstract class PageEdits with _$PageEdits {
  const factory PageEdits({
    /// null = full image.
    Quad? crop,
    @Default(0) int quarterTurns,
    @Default(FilterType.auto) FilterType filter,
    /// -100..100
    @Default(0) double brightness,
    /// -100..100
    @Default(0) double contrast,
    /// ID card / passport: the warp is forced to this width / height (real
    /// card shape, landscape), as in the reference `warp()`. null = free.
    double? outputAspect,

    /// Signatures and date stamps (feature 4), drawn over the finished page.
    @Default(<PageOverlay>[]) List<PageOverlay> overlays,

    /// Passport photo (feature 5): the print size in millimetres.
    double? photoWidthMm,
    double? photoHeightMm,

    /// Passport photo background: the person mask for the whole upright
    /// photo (8-bit PNG, any size; sharper inside the crop, see
    /// `BackgroundSegmenter.maskFor`) and the colour behind them. The
    /// mask is also kept with an original background, for Enhance. Applied as
    /// the crop is rendered, so every output gets it.
    @JsonKey(unknownEnumValue: PhotoBackground.darkBlue)
    @Default(PhotoBackground.original)
    PhotoBackground photoBackground,
    String? backgroundMaskPath,

    /// Passport photo touch-up, before the background. Off for photos saved
    /// before it existed, so they keep their look.
    @JsonKey(unknownEnumValue: PhotoEnhance.off)
    @Default(PhotoEnhance.off)
    PhotoEnhance photoEnhance,

    /// Round 11b, P1-14: the face in a passport photo (ML Kit), as
    /// [x0, y0, x1, y1] fractions of the upright photo, for Enhance's
    /// face brightening. Null: found from the person mask instead.
    List<double>? faceBox,

    /// Round 11, P0-14: the user placed the corners in Adjust edges, so the
    /// bent-page warp keeps them exactly (only the sides may bend). Pages
    /// saved before it existed read as true: their corners never move.
    @JsonKey(defaultValue: true) @Default(false) bool cornersFixed,

    /// Round 11, P1-11: "Remove" was tapped for the fingers found on this
    /// page; [fingerMaskPath] is their mask (8-bit PNG, the cropped and
    /// turned page at any size). Applied after the filter, so a filter
    /// change keeps them removed.
    @Default(false) bool fingersRemoved,
    String? fingerMaskPath,
  }) = _PageEdits;
  const PageEdits._();

  factory PageEdits.fromJson(Map<String, dynamic> json) =>
      _$PageEditsFromJson(json);

  int get normalizedTurns => ((quarterTurns % 4) + 4) % 4;

  /// What decides the cropped page's pixels (crop, bend, turns, card
  /// shape): cache names of crop-level renders use it.
  int get geometryKey => Object.hash(crop, normalizedTurns, outputAspect, cornersFixed);

  PageEdits rotateLeft() => copyWith(quarterTurns: normalizedTurns - 1);
  PageEdits rotateRight() => copyWith(quarterTurns: normalizedTurns + 1);

  /// Brightness / contrast as a per-channel linear map `out = a·in + b`
  /// (0..255, clamped). Used by the export pipeline and, unchanged, by the
  /// live colour matrix on the Enhance screen so both look identical.
  ({double alpha, double beta}) get sliderTransform {
    final c = contrast.clamp(-100, 100) / 100;
    final alpha = c >= 0 ? 1 + c : 1 + c * 0.75;
    final beta = brightness.clamp(-100, 100) * 1.0 + 128 * (1 - alpha);
    return (alpha: alpha, beta: beta);
  }

  bool get hasSliders => brightness != 0 || contrast != 0;

  /// A Document page: not an ID card / passport side (forced card shape)
  /// or a passport photo.
  bool get isDocumentPage => outputAspect == null && photoWidthMm == null;

  /// Enhance-only settings (filter + sliders), used by "apply to all".
  PageEdits applyLook(PageEdits from) => copyWith(
        filter: from.filter,
        brightness: from.brightness,
        contrast: from.contrast,
      );
}
