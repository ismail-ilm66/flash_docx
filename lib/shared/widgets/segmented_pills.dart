import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flutter/material.dart';

/// Single-choice segmented control. Two looks from the design:
/// - default: a sunken track with the chosen segment raised as a tile
///   (Extracted text scope, Print output);
/// - [accent]: a bordered card with the chosen segment filled in the accent
///   colour (Settings › Appearance).
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    super.key,
    this.scrollable = false,
    this.accent = false,
    this.height = 40,
    this.labelSize = 14,
    this.badgeOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool scrollable;
  final bool accent;
  final double height;
  final double labelSize;

  /// Optional trailing mark per segment (e.g. the video icon on a gated one).
  final Widget? Function(T)? badgeOf;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pills = <Widget>[
      for (final (i, v) in values.indexed) ...[
        if (i > 0) const SizedBox(width: Space.x1),
        _Pill(
          label: labelOf(v),
          selected: v == selected,
          onTap: () => onChanged(v),
          expand: !scrollable,
          accent: accent,
          height: height,
          labelSize: labelSize,
          badge: badgeOf?.call(v),
        ),
      ],
    ];
    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: pills,
    );
    return Container(
      padding: const EdgeInsets.all(Space.x1),
      decoration: BoxDecoration(
        color: accent ? c.surface : c.surface2,
        borderRadius: accent ? Radii.lgR : Radii.mdR,
        border: accent ? Border.all(color: c.border) : null,
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
    required this.accent,
    required this.height,
    required this.labelSize,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;
  final bool accent;
  final double height;
  final double labelSize;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = accent ? BorderRadius.circular(12) : Radii.smR;
    final bg = !selected
        ? Colors.transparent
        : accent
            ? c.accent
            : c.surface;
    final fg = !selected
        ? c.muted
        : accent
            ? c.onAccent
            : c.text;
    final pill = Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: Motion.normal,
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: fg,
                    fontSize: labelSize,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge!,
              ],
            ],
          ),
        ),
      ),
    );
    return expand ? Expanded(child: pill) : pill;
  }
}
