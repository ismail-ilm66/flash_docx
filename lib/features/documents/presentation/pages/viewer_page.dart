import 'dart:io';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/constants/sizes.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/utils/date_format.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/cubit/viewer_cubit.dart';
import 'package:flash_dox/features/documents/presentation/widgets/document_menu.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/editor/presentation/widgets/page_strip.dart';
import 'package:flash_dox/features/export/presentation/share_sheet.dart';
import 'package:flash_dox/features/scanner/presentation/add_pages.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ViewerPage extends StatelessWidget {
  const ViewerPage({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ViewerCubit>(param1: documentId),
      child: const _ViewerView(),
    );
  }
}

class _ViewerView extends StatefulWidget {
  const _ViewerView();

  @override
  State<_ViewerView> createState() => _ViewerViewState();
}

class _ViewerViewState extends State<_ViewerView> {
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _jump(int i) {
    if (!_pageCtrl.hasClients) return;
    _pageCtrl.animateToPage(i, duration: Motion.normal, curve: Curves.easeOutCubic);
  }

  Future<void> _menu(BuildContext context, ViewerState s) async {
    final l = context.l10n;
    final cubit = context.read<ViewerCubit>();
    final doc = s.document!;
    final action = await AppBottomSheet.show<_ViewerAction>(
      context,
      builder: (ctx) => AppBottomSheet(
        title: doc.title,
        child: Column(
          children: [
            SheetAction(label: l.viewerRename, leading: const AppIcon(AppIcons.rename), onTap: () => Navigator.of(ctx).pop(_ViewerAction.rename)),
            if (doc.pages.length > 1)
              SheetAction(label: l.viewerDeletePage, leading: const AppIcon(AppIcons.delete), onTap: () => Navigator.of(ctx).pop(_ViewerAction.deletePage)),
            SheetAction(label: l.viewerDelete, leading: const AppIcon(AppIcons.delete), destructive: true, onTap: () => Navigator.of(ctx).pop(_ViewerAction.delete)),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _ViewerAction.rename:
        await renameDocumentFlow(context, doc, cubit.rename);
      case _ViewerAction.deletePage:
        final ok = await AppDialog.confirm(context, title: l.deletePageTitle, body: l.deletePageBody, confirmLabel: l.commonDelete, destructive: true);
        if (ok) await cubit.deleteCurrentPage();
      case _ViewerAction.delete:
        final done = await deleteDocumentFlow(context, doc, cubit.delete);
        if (done && context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<ViewerCubit, ViewerState>(
      listenWhen: (a, b) => a.deleted != b.deleted,
      listener: (context, s) {
        if (s.deleted && context.canPop()) context.pop();
      },
      builder: (context, s) {
        final cubit = context.read<ViewerCubit>();
        final doc = s.document;
        if (s.loading) {
          return const AppScaffold(topBar: AppTopBar(), body: Center(child: CircularProgressIndicator()));
        }
        if (doc == null) {
          return AppScaffold(topBar: const AppTopBar(), body: ErrorView(failure: s.failure));
        }
        final pages = s.pages;
        final cur = s.current;
        final multi = pages.length > 1;
        void edit() => context.push(
              Routes.adjust,
              extra: EditorArgs(pages: pages, mode: doc.mode, documentId: doc.id, initialIndex: s.index),
            );
        Future<void> addPages() async {
          final added = await collectNewPages(context, mode: doc.mode);
          if (added == null || added.isEmpty || !context.mounted) return;
          final err = await cubit.addPages(added);
          if (err != null && context.mounted) context.showSnack(failureMessage(context, err), error: true);
        }

        return AppScaffold(
          topBar: AppTopBar(
            centerTitle: false,
            titleWidget: _TitleButton(
              title: doc.title,
              subtitle: '${l.pagesCount(pages.length)} · ${_stamp(context, doc.updatedAt)}',
              onTap: () => renameDocumentFlow(context, doc, cubit.rename),
            ),
            actions: [
              IconButton(
                tooltip: l.commonMore,
                onPressed: () => _menu(context, s),
                icon: AppIcon(AppIcons.more, size: 20, color: c.text),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: c.stage,
                  child: pages.isEmpty
                      ? EmptyState(title: l.homeEmptyTitle)
                      : Column(
                          children: [
                            Expanded(
                              child: PageView.builder(
                                controller: _pageCtrl,
                                itemCount: pages.length,
                                onPageChanged: cubit.select,
                                itemBuilder: (context, i) {
                                  final path = pages[i].displayPath;
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(Space.x10, Space.x6, Space.x10, Space.x3),
                                    child: InteractiveViewer(
                                      maxScale: 5,
                                      child: Center(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: c.border),
                                            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 6))],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: Image.file(
                                              File(path),
                                              key: ValueKey(path),
                                              gaplessPlayback: true,
                                              fit: BoxFit.contain,
                                              // Until the processed cache is
                                              // ready this is the 12 MP original;
                                              // never decode it at full size.
                                              cacheWidth: RenderPx.previewLongEdge,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Container(
                              height: 26,
                              margin: const EdgeInsets.only(bottom: Space.x4),
                              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                              decoration: BoxDecoration(color: c.chip, borderRadius: Radii.pillR),
                              alignment: Alignment.center,
                              child: Text(
                                l.viewerCounter(s.index + 1, pages.length),
                                style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Space.x3, bottom: Space.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: PageStrip(
                        pages: pages,
                        index: s.index,
                        onSelect: _jump,
                        onReorder: multi ? cubit.reorder : null,
                        pathOf: (p) => p.thumbPath ?? p.displayPath,
                        cacheKeyOf: (p) => p.thumbPath,
                        trailing: AddPageTile(onTap: addPages),
                      ),
                    ),
                    if (multi)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.x4, bottom: 12),
                        child: Text(
                          l.viewerHoldToReorder,
                          style: context.text.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, 14, Space.x4, 18),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 10,
                          child: ToolbarAction(
                            icon: AppIcons.edit,
                            label: l.viewerEdit,
                            iconSize: 22,
                            onPressed: cur == null ? null : edit,
                          ),
                        ),
                        Expanded(
                          flex: 10,
                          child: ToolbarAction(
                            icon: AppIcons.text,
                            label: l.viewerText,
                            iconSize: 22,
                            onPressed: cur == null ? null : () => context.push('${Routes.text(doc.id)}?page=${cur.id}'),
                          ),
                        ),
                        if (doc.mode.supportsPrintLayout)
                          Expanded(
                            flex: 10,
                            child: ToolbarAction(
                              icon: AppIcons.print,
                              label: l.viewerPrint,
                              iconSize: 22,
                              onPressed: () => context.push(Routes.print(doc.id)),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 14,
                          child: PrimaryButton(
                            label: l.viewerShare,
                            icon: AppIcons.share,
                            height: 48,
                            onPressed: pages.isEmpty ? null : () => showShareSheet(context, doc),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Today, 10:42" / "Yesterday, 10:42" / "Oct 3, 10:42".
String _stamp(BuildContext context, DateTime d) {
  final l = context.l10n;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final time = DateFormat.Hm().format(d);
  if (day == today) return l.dateTodayAt(time);
  if (day == today.subtract(const Duration(days: 1))) return l.dateYesterdayAt(time);
  return '${DateFmt.relative(d)}, $time';
}

/// Title + subtitle with a pencil: tap to rename.
class _TitleButton extends StatelessWidget {
  const _TitleButton({required this.title, required this.subtitle, required this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${context.l10n.renameTitle}: $title',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.smR,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x1),
            child: Row(
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 1),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: c.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                AppIcon(AppIcons.rename, size: 16, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ViewerAction { rename, deletePage, delete }
