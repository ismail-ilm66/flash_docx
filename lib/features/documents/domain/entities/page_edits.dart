import 'package:flash_dox/features/documents/domain/entities/enums.dart';
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
  }) = _PageEdits;
  const PageEdits._();

  factory PageEdits.fromJson(Map<String, dynamic> json) =>
      _$PageEditsFromJson(json);

  int get normalizedTurns => ((quarterTurns % 4) + 4) % 4;

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

  /// Enhance-only settings (filter + sliders), used by "apply to all".
  PageEdits applyLook(PageEdits from) => copyWith(
        filter: from.filter,
        brightness: from.brightness,
        contrast: from.contrast,
      );
}
