import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Horizontal strip of numbered page thumbnails with the selected one
/// ringed. [trailing] sits after the last page (e.g. the "add pages" tile).
class PageStrip extends StatelessWidget {
  const PageStrip({
    required this.pages,
    required this.index,
    required this.onSelect,
    required this.pathOf,
    super.key,
    this.cacheKeyOf,
    this.onLongPress,
    this.trailing,
    this.size = 52,
  });

  final List<ScanPage> pages;
  final int index;
  final ValueChanged<int> onSelect;
  final String? Function(ScanPage) pathOf;
  final Object? Function(ScanPage)? cacheKeyOf;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final h = size * 68 / 52;
    return SizedBox(
      // Room for the number badge hanging below each thumb.
      height: h + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        itemCount: pages.length + (trailing == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == pages.length) return Align(alignment: Alignment.topCenter, child: trailing);
          return Align(
            alignment: Alignment.topCenter,
            child: PageThumb(
              path: pathOf(pages[i]),
              number: i + 1,
              selected: i == index,
              size: size,
              cacheKey: cacheKeyOf?.call(pages[i]),
              semanticLabel: l.pageOfTotal(i + 1, pages.length),
              onTap: () => onSelect(i),
              onLongPress: onLongPress,
            ),
          );
        },
      ),
    );
  }
}
