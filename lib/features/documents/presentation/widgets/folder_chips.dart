import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Home folder chips (feature 3): All · Bills · IDs · Education · Receipts ·
/// Other, each with its count. Folders with nothing in them are left out.
class FolderChips extends StatelessWidget {
  const FolderChips({required this.counts, required this.selected, required this.onSelected, super.key});

  final Map<DocFolder, int> counts;

  /// null = All.
  final DocFolder? selected;
  final ValueChanged<DocFolder?> onSelected;

  /// All · IDs · Photos · Office · Bills · Education · Receipts · Other
  /// (round 11 order).
  static const List<DocFolder> order = [
    DocFolder.ids,
    DocFolder.photos,
    DocFolder.office,
    DocFolder.bills,
    DocFolder.education,
    DocFolder.receipts,
    DocFolder.other,
  ];

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final shown = [for (final f in order) if ((counts[f] ?? 0) > 0 || f == selected) f];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.x5),
      child: Row(
        children: [
          _Chip(label: context.l10n.folderAll, count: total, selected: selected == null, onTap: () => onSelected(null), dot: folderDotColor(null)),
          for (final f in shown) ...[
            const SizedBox(width: Space.x2),
            _Chip(label: folderLabel(context, f), count: counts[f] ?? 0, selected: selected == f, onTap: () => onSelected(f), dot: folderDotColor(f)),
          ],
        ],
      ),
    );
  }
}

/// Round 11 (Home redesign, option C): each folder's dot colour, the same
/// in both themes.
Color folderDotColor(DocFolder? f) => switch (f) {
  null => const Color(0xFFFFC233),
  DocFolder.ids => const Color(0xFF3B82F6),
  DocFolder.photos => const Color(0xFFF97316),
  DocFolder.office => const Color(0xFF8B5CF6),
  DocFolder.bills => const Color(0xFF14B8A6),
  DocFolder.education => const Color(0xFFEAB308),
  DocFolder.receipts => const Color(0xFFEC4899),
  DocFolder.other => const Color(0xFF9CA3AF),
};

/// A pill: 40 dp, a 10 dp colour dot, the name and the count (70 %). The
/// selected one is filled with the text colour, its text inverted.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.selected, required this.onTap, required this.dot});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.bg : c.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.text : c.surface,
        shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label, maxLines: 1, style: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  maxLines: 1,
                  style: context.text.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
