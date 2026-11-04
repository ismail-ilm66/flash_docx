import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

/// Marks an option that needs a rewarded video. Compact: the small video
/// glyph; full: the "▶ VIDEO" pill.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key, this.compact = false, this.size = 14});

  final bool compact;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    if (compact) {
      return Semantics(
        label: l.unlockTitle,
        child: AppIcon(AppIcons.video, size: size, color: c.accentText),
      );
    }
    return Semantics(
      label: l.unlockTitle,
      excludeSemantics: true,
      child: Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: Radii.pillR),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.play, size: 10, color: c.accentText),
            const SizedBox(width: 3),
            Text(
              l.shareWatchVideo.toUpperCase(),
              style: context.text.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: c.accentText,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill chip. Selected = inverted (text colour fill), as on the share
/// sheet's page-size row.
class OptionChip extends StatelessWidget {
  const OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.gated = false,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool gated;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = !enabled
        ? c.muted.withValues(alpha: 0.5)
        : selected
            ? (c.isDark ? c.bg : c.surface)
            : c.text;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: Radii.pillR,
        child: AnimatedContainer(
          duration: Motion.normal,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected ? c.text : Colors.transparent,
            borderRadius: Radii.pillR,
            border: Border.all(color: selected ? c.text : c.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.text.labelMedium?.copyWith(
                  fontSize: 13,
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (gated) ...[
                const SizedBox(width: 6),
                const VideoBadge(compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable card: bold title, small muted caption. Selected = accent ring
/// on a soft accent fill (share sheet format and quality, print copies).
class OptionCard extends StatelessWidget {
  const OptionCard({
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
    this.subtitle,
    this.icon,
    this.gated = false,
    this.trailing,
    this.centered = false,
    this.height,
    this.titleSize = 14,
  });

  final String title;
  final String? subtitle;
  final AppIcons? icon;
  final bool selected;
  final VoidCallback onTap;

  /// Shows the "▶ VIDEO" pill beside the title ([centered] cards show the
  /// compact glyph instead).
  final bool gated;
  final Widget? trailing;
  final bool centered;
  final double? height;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleRow = Row(
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Flexible(
          child: Text(
            title,
            style: context.text.titleSmall?.copyWith(fontSize: titleSize, fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (gated) ...[
          SizedBox(width: centered ? 4 : 6),
          VideoBadge(compact: centered),
        ],
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.mdR,
        child: AnimatedContainer(
          duration: Motion.normal,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: centered ? Space.x2 : 14, vertical: Space.x2),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : Colors.transparent,
            borderRadius: Radii.mdR,
            border: selected
                ? Border.all(color: c.accent, width: 2)
                : Border.all(color: c.borderStrong),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                AppIcon(icon!, color: selected ? c.accentText : c.text),
                const SizedBox(width: Space.x3),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Uppercase section label used on sheets and settings ("FORMAT").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = EdgeInsets.zero});

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text.toUpperCase(),
          style: context.text.labelMedium?.copyWith(
            color: context.colors.muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
}
