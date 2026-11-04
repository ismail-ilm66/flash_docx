import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Label + signed value above a slider. When the range straddles zero the
/// active part of the track runs from the centre to the thumb.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
    this.min = -100,
    this.max = 100,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  String get _valueText {
    final v = value.round();
    return v > 0 && min < 0 ? '+$v' : '$v';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = SliderTheme.of(context);
    final origin = min < 0 && max > 0 ? (0 - min) / (max - min) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: context.text.labelLarge?.copyWith(fontSize: 13)),
            const Spacer(),
            Text(
              _valueText,
              style: context.text.labelLarge?.copyWith(
                fontSize: 13,
                color: c.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x1),
        SizedBox(
          height: 28,
          child: SliderTheme(
            data: theme.copyWith(
              trackHeight: 4,
              trackShape: _OriginTrackShape(origin),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 2, pressedElevation: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              semanticFormatterCallback: (_) => _valueText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-width rounded track; the active colour spans [origin] → thumb.
class _OriginTrackShape extends RoundedRectSliderTrackShape {
  const _OriginTrackShape(this.origin);

  /// 0–1 position of the track's zero point.
  final double origin;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    Offset offset = Offset.zero,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final h = sliderTheme.trackHeight ?? 4;
    // Leave room for the thumb so it never clips at the ends.
    const inset = 11.0;
    final top = offset.dy + (parentBox.size.height - h) / 2;
    return Rect.fromLTWH(offset.dx + inset, top, parentBox.size.width - inset * 2, h);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(parentBox: parentBox, sliderTheme: sliderTheme, offset: offset);
    final canvas = context.canvas;
    final r = Radius.circular(rect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey,
    );
    final zero = rect.left + rect.width * origin;
    final a = zero < thumbCenter.dx ? zero : thumbCenter.dx;
    final b = zero < thumbCenter.dx ? thumbCenter.dx : zero;
    if (b - a > 0.5) {
      canvas.drawRect(
        Rect.fromLTRB(a, rect.top, b, rect.bottom),
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.amber,
      );
    }
  }
}
