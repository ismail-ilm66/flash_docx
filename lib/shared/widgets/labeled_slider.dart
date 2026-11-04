import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x1),
          child: Row(
            children: [
              Text(label, style: context.text.labelMedium?.copyWith(color: c.muted)),
              const Spacer(),
              Text(
                value.round().toString(),
                style: context.text.labelMedium?.copyWith(
                  color: c.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          label: value.round().toString(),
        ),
      ],
    );
  }
}
