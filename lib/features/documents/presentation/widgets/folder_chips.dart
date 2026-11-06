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

  static const List<DocFolder> order = [DocFolder.bills, DocFolder.ids, DocFolder.education, DocFolder.receipts, DocFolder.other];

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final shown = [for (final f in order) if ((counts[f] ?? 0) > 0 || f == selected) f];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.x5),
      child: Row(
        children: [
          _Chip(label: context.l10n.folderAll, count: total, selected: selected == null, onTap: () => onSelected(null)),
          for (final f in shown) ...[
            const SizedBox(width: Space.x2),
            _Chip(label: folderLabel(context, f), count: counts[f] ?? 0, selected: selected == f, onTap: () => onSelected(f)),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

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
        color: selected ? c.text : Colors.transparent,
        shape: StadiumBorder(side: selected ? BorderSide.none : BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: context.text.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? c.bg : c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
