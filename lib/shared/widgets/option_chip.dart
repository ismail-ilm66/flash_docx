import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/shared/widgets/app_icon.dart';
import 'package:flash_dox/shared/widgets/app_icons.dart';
import 'package:flutter/material.dart';

/// Small "video" tag shown on options that need a rewarded video.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.x1 : Space.x2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: Radii.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.video, size: 12, color: c.accentText),
          if (!compact) ...[
            const SizedBox(width: 3),
            Text(
              context.l10n.shareWatchVideo,
              style: context.text.labelSmall?.copyWith(color: c.accentText),
            ),
          ],
        ],
      ),
    );
  }
}

/// Selectable chip with an optional [VideoBadge].
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
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: Radii.pillR,
        child: AnimatedContainer(
          duration: Motion.normal,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: Space.x4),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface2,
            borderRadius: Radii.pillR,
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.text.labelLarge?.copyWith(
                  color: !enabled
                      ? c.muted.withValues(alpha: 0.5)
                      : selected
                          ? c.accentText
                          : c.text,
                ),
              ),
              if (gated) ...[
                const SizedBox(width: Space.x2),
                const VideoBadge(compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Larger selectable card with title + description.
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
  });

  final String title;
  final String? subtitle;
  final AppIcons? icon;
  final bool selected;
  final VoidCallback onTap;
  final bool gated;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.lgR,
        child: AnimatedContainer(
          duration: Motion.normal,
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface,
            borderRadius: Radii.lgR,
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                AppIcon(icon!, color: selected ? c.accentText : c.text),
                const SizedBox(width: Space.x3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: context.text.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (gated) ...[
                          const SizedBox(width: Space.x2),
                          const VideoBadge(),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: context.text.bodySmall?.copyWith(color: c.muted),
                      ),
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
