import 'dart:io';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/cubit/viewer_cubit.dart';
import 'package:flash_dox/features/documents/presentation/widgets/document_menu.dart';
import 'package:flash_dox/features/documents/presentation/widgets/reorder_sheet.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/editor/presentation/widgets/page_strip.dart';
import 'package:flash_dox/features/export/presentation/share_sheet.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
            SheetAction(label: l.viewerAddPages, leading: const AppIcon(AppIcons.addPage), onTap: () => Navigator.of(ctx).pop(_ViewerAction.addPages)),
            if (doc.pages.length > 1)
              SheetAction(label: l.viewerReorder, leading: const AppIcon(AppIcons.reorder), onTap: () => Navigator.of(ctx).pop(_ViewerAction.reorder)),
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
      case _ViewerAction.addPages:
        await context.push(Routes.camera, extra: CameraArgs(mode: ScanMode.batch, addToDocumentId: doc.id));
      case _ViewerAction.reorder:
        final ids = await showReorderSheet(context, doc.sortedPages);
        if (ids != null) await cubit.reorder(ids);
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
        return AppScaffold(
          topBar: AppTopBar(
            title: doc.title,
            subtitle: '${modeLabel(context, doc.mode)} · ${l.pagesCount(pages.length)}',
            actions: [
              IconButton(
                tooltip: 'More',
                onPressed: () => _menu(context, s),
                icon: const AppIcon(AppIcons.more),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: pages.isEmpty
                    ? EmptyState(title: l.homeEmptyTitle)
                    : PageView.builder(
                        controller: _pageCtrl,
                        itemCount: pages.length,
                        onPageChanged: cubit.select,
                        itemBuilder: (context, i) {
                          final p = pages[i];
                          final path = p.displayPath;
                          return Padding(
                            padding: const EdgeInsets.all(Space.x3),
                            child: InteractiveViewer(
                              maxScale: 5,
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: Radii.smR,
                                  child: Image.file(
                                    File(path),
                                    key: ValueKey(path),
                                    gaplessPlayback: true,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (pages.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x1),
                  child: Text(
                    l.viewerPageOf(s.index + 1, pages.length),
                    style: context.text.labelSmall?.copyWith(color: c.muted),
                  ),
                ),
                PageStrip(
                  pages: pages,
                  index: s.index,
                  onSelect: _jump,
                  pathOf: (p) => p.thumbPath ?? p.displayPath,
                  cacheKeyOf: (p) => p.thumbPath,
                ),
              ],
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.x1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ToolbarAction(
                          icon: AppIcons.edit,
                          label: l.viewerEdit,
                          onPressed: cur == null
                              ? null
                              : () => context.push(
                                    Routes.adjust,
                                    extra: EditorArgs(
                                      pages: pages,
                                      mode: doc.mode,
                                      documentId: doc.id,
                                      initialIndex: s.index,
                                    ),
                                  ),
                        ),
                        ToolbarAction(
                          icon: AppIcons.text,
                          label: l.viewerText,
                          onPressed: cur == null
                              ? null
                              : () => context.push('${Routes.text(doc.id)}?page=${cur.id}'),
                        ),
                        if (doc.mode.supportsPrintLayout)
                          ToolbarAction(
                            icon: AppIcons.print,
                            label: l.viewerPrint,
                            onPressed: () => context.push(Routes.print(doc.id)),
                          ),
                        ToolbarAction(
                          icon: AppIcons.share,
                          label: l.viewerShare,
                          active: true,
                          onPressed: pages.isEmpty ? null : () => showShareSheet(context, doc),
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

enum _ViewerAction { rename, addPages, reorder, deletePage, delete }
