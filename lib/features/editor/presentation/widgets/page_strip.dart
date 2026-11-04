import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Horizontal strip of page thumbnails with the selected one highlighted.
class PageStrip extends StatelessWidget {
  const PageStrip({
    required this.pages,
    required this.index,
    required this.onSelect,
    required this.pathOf,
    super.key,
    this.cacheKeyOf,
    this.size = 48,
  });

  final List<ScanPage> pages;
  final int index;
  final ValueChanged<int> onSelect;
  final String? Function(ScanPage) pathOf;
  final Object? Function(ScanPage)? cacheKeyOf;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size / 0.75 + Space.x2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
        itemCount: pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: Space.x2),
        itemBuilder: (context, i) => PageThumb(
          path: pathOf(pages[i]),
          number: i + 1,
          selected: i == index,
          size: size,
          cacheKey: cacheKeyOf?.call(pages[i]),
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}
