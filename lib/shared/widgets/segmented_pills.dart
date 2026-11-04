import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Pill-shaped single-choice segment. Used for text tabs, print outputs,
/// theme, share format…
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    super.key,
    this.scrollable = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pills = [
      for (final v in values)
        _Pill(
          label: labelOf(v),
          selected: v == selected,
          onTap: () => onChanged(v),
          expand: !scrollable,
        ),
    ];
    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: pills,
    );
    return Container(
      padding: const EdgeInsets.all(Space.x1),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: Radii.pillR,
        border: Border.all(color: c.border),
      ),
      child: scrollable
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
          : row,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.expand,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pill = Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.pillR,
        child: AnimatedContainer(
          duration: Motion.normal,
          curve: Curves.easeOutCubic,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Space.x4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: Radii.pillR,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelLarge?.copyWith(
              color: selected ? c.onAccent : c.muted,
            ),
          ),
        ),
      ),
    );
    return expand ? Expanded(child: pill) : pill;
  }
}
