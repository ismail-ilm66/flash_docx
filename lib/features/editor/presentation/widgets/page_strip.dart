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
    this.onReorder,
    this.trailing,
    this.size = 52,
  });

  final List<ScanPage> pages;
  final int index;
  final ValueChanged<int> onSelect;
  final String? Function(ScanPage) pathOf;
  final Object? Function(ScanPage)? cacheKeyOf;
  final VoidCallback? onLongPress;

  /// When set, thumbnails can be long-pressed and dragged to reorder; the
  /// callback receives the page ids in their new order.
  final ValueChanged<List<String>>? onReorder;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final h = size * 68 / 52;
    if (onReorder != null && pages.length > 1) {
      return SizedBox(
        height: h + 12,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.x4),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, __) => Material(color: Colors.transparent, child: child),
          footer: trailing == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Align(alignment: Alignment.topCenter, child: trailing),
                ),
          itemCount: pages.length,
          onReorder: (o, n) {
            if (n > o) n--;
            final ids = pages.map((p) => p.id).toList();
            final id = ids.removeAt(o);
            ids.insert(n, id);
            onReorder!(ids);
          },
          itemBuilder: (context, i) => Padding(
            key: ValueKey(pages[i].id),
            padding: EdgeInsets.only(right: i == pages.length - 1 ? 0 : 10),
            child: ReorderableDelayedDragStartListener(
              index: i,
              child: Align(
                alignment: Alignment.topCenter,
                child: PageThumb(
                  path: pathOf(pages[i]),
                  number: i + 1,
                  selected: i == index,
                  size: size,
                  cacheKey: cacheKeyOf?.call(pages[i]),
                  semanticLabel: l.pageOfTotal(i + 1, pages.length),
                  onTap: () => onSelect(i),
                ),
              ),
            ),
          ),
        ),
      );
    }
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
