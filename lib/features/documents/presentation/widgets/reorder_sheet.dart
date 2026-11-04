import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Drag-to-reorder list. Resolves the new page id order, or null.
Future<List<String>?> showReorderSheet(BuildContext context, List<ScanPage> pages) {
  return AppBottomSheet.show<List<String>>(
    context,
    builder: (ctx) => _ReorderSheet(pages: pages),
  );
}

class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.pages});
  final List<ScanPage> pages;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final List<ScanPage> _pages = [...widget.pages];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final h = MediaQuery.sizeOf(context).height * 0.7;
    return AppBottomSheet(
      title: l.viewerReorder,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                itemCount: _pages.length,
                onReorder: (o, n) => setState(() {
                  if (n > o) n--;
                  final p = _pages.removeAt(o);
                  _pages.insert(n, p);
                }),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return ListTile(
                    key: ValueKey(p.id),
                    leading: PageThumb(path: p.thumbPath ?? p.displayPath, size: 40, cacheKey: p.thumbPath),
                    title: Text('${i + 1}', style: context.text.titleSmall),
                    trailing: AppIcon(AppIcons.dragHandle, color: c.muted),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: PrimaryButton(
                label: l.commonDone,
                onPressed: () => Navigator.of(context).pop(_pages.map((p) => p.id).toList()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
