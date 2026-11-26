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
    this.onHold,
    this.checkedOf,
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

  /// A page held without being dragged (round 11, P0-13: starts selecting).
  final ValueChanged<int>? onHold;

  /// Selecting: each page shows a check box, ticked when this is true; taps
  /// go to [onSelect] and nothing can be dragged.
  final bool Function(ScanPage)? checkedOf;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final h = size * 68 / 52;
    Widget thumb(int i, {VoidCallback? onLongPress}) {
      final t = PageThumb(
        path: pathOf(pages[i]),
        number: i + 1,
        selected: checkedOf == null && i == index,
        size: size,
        cacheKey: cacheKeyOf?.call(pages[i]),
        semanticLabel: l.pageOfTotal(i + 1, pages.length),
        onTap: () => onSelect(i),
        onLongPress: onLongPress,
      );
      final checked = checkedOf?.call(pages[i]);
      if (checked == null) return t;
      final c = context.colors;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          t,
          Positioned(
            top: 3,
            right: 3,
            child: IgnorePointer(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? c.accent : Colors.black.withValues(alpha: 0.35),
                  border: Border.all(color: checked ? c.accent : Colors.white, width: 1.5),
                ),
                child: checked ? Icon(Icons.check_rounded, size: 14, color: c.onAccent) : null,
              ),
            ),
          ),
        ],
      );
    }

    if (onReorder != null && pages.length > 1 && checkedOf == null) {
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
            // Held but not moved: not a reorder.
            if (n == o || n == o + 1) {
              onHold?.call(o);
              return;
            }
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
              child: Align(alignment: Alignment.topCenter, child: thumb(i)),
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
            child: thumb(i, onLongPress: onHold != null && checkedOf == null ? () => onHold!(i) : onLongPress),
          );
        },
      ),
    );
  }
}
