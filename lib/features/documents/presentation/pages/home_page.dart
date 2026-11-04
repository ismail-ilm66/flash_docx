import 'dart:async';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/share_in_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/cubit/home_cubit.dart';
import 'package:flash_dox/features/documents/presentation/widgets/document_menu.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/export/presentation/share_sheet.dart';
import 'package:flash_dox/features/scanner/data/import_service.dart';
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeCubit>(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  StreamSubscription<List<String>>? _shareSub;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    final shareIn = getIt<ShareInService>();
    unawaited(shareIn.initialShare().then(_onSharedIn));
    _shareSub = shareIn.shares.listen(_onSharedIn);
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Future<void> _onSharedIn(List<String> paths) async {
    if (paths.isEmpty) return;
    await _startImport(paths, copySource: false);
  }

  Future<void> _importFrom({required bool gallery}) async {
    final svc = getIt<ImportService>();
    final r = gallery ? await svc.fromGallery() : await svc.fromFiles();
    if (!mounted) return;
    await r.fold(
      (f) async {
        if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
      },
      _startImport,
    );
  }

  Future<void> _startImport(List<String> paths, {bool copySource = true}) async {
    if (_importing) return;
    setState(() => _importing = true);
    final mode = paths.length > 1 ? ScanMode.batch : ScanMode.single;
    final r = await getIt<PreparePages>()(paths, mode: mode, copySource: copySource);
    if (!mounted) return;
    setState(() => _importing = false);
    r.fold(
      (f) => context.showSnack(failureMessage(context, f), error: true),
      (pages) => context.push(Routes.adjust, extra: EditorArgs(pages: pages, mode: mode)),
    );
  }

  Future<void> _onMore(BuildContext context, ScanDocument doc) async {
    final cubit = context.read<HomeCubit>();
    final action = await showDocumentMenu(context, doc);
    if (action == null || !context.mounted) return;
    switch (action) {
      case DocumentMenuAction.rename:
        await renameDocumentFlow(context, doc, (t) => cubit.rename(doc.id, t));
      case DocumentMenuAction.share:
        await showShareSheet(context, doc);
      case DocumentMenuAction.delete:
        await deleteDocumentFlow(context, doc, () => cubit.delete(doc.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, s) {
        final showEmpty = !s.loading && s.documents.isEmpty && s.search.isEmpty;
        return AppScaffold(
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: c.bg,
                    title: Row(
                      children: [
                        AppIcon(AppIcons.bolt, color: c.accent),
                        const SizedBox(width: Space.x2),
                        Text(l.homeTitle, style: context.text.headlineSmall),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
                    sliver: SliverList.list(
                      children: [
                        _SectionTitle(l.homeQuickActions),
                        const SizedBox(height: Space.x2),
                        GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: Space.x2,
                          crossAxisSpacing: Space.x2,
                          childAspectRatio: 0.9,
                          children: [
                            QuickActionTile(
                              icon: AppIcons.single,
                              label: l.modeSingle,
                              onTap: () => context.push(Routes.camera, extra: const CameraArgs(mode: ScanMode.single)),
                            ),
                            QuickActionTile(
                              icon: AppIcons.batch,
                              label: l.modeBatch,
                              onTap: () => context.push(Routes.camera, extra: const CameraArgs(mode: ScanMode.batch)),
                            ),
                            QuickActionTile(
                              icon: AppIcons.idCard,
                              label: l.modeIdCard,
                              onTap: () => context.push(Routes.camera, extra: const CameraArgs(mode: ScanMode.idCard)),
                            ),
                            QuickActionTile(
                              icon: AppIcons.passport,
                              label: l.modePassport,
                              onTap: () => context.push(Routes.camera, extra: const CameraArgs(mode: ScanMode.passport)),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.x2),
                        Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                label: l.homeImportGallery,
                                icon: AppIcons.gallery,
                                onPressed: () => _importFrom(gallery: true),
                              ),
                            ),
                            const SizedBox(width: Space.x2),
                            Expanded(
                              child: SecondaryButton(
                                label: l.homeImportFiles,
                                icon: AppIcons.files,
                                onPressed: () => _importFrom(gallery: false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.x6),
                        _SectionTitle(l.homeRecentActivity),
                        const SizedBox(height: Space.x2),
                        if (!showEmpty)
                          TextField(
                            onChanged: context.read<HomeCubit>().search,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: l.homeSearchHint,
                              prefixIcon: AppIcon(AppIcons.search, color: c.muted),
                            ),
                          ),
                        const SizedBox(height: Space.x3),
                      ],
                    ),
                  ),
                  if (showEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(title: l.homeEmptyTitle, body: l.homeEmptyBody),
                    )
                  else if (s.failure != null)
                    SliverFillRemaining(hasScrollBody: false, child: ErrorView(failure: s.failure))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Sizes.navBar + Space.x8),
                      sliver: SliverList.separated(
                        itemCount: s.documents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: Space.x2),
                        itemBuilder: (context, i) {
                          final d = s.documents[i];
                          return DocumentTile(
                            document: d,
                            onTap: () => context.push(Routes.viewer(d.id)),
                            onMore: () => _onMore(context, d),
                          );
                        },
                      ),
                    ),
                ],
              ),
              if (_importing) ProgressOverlay(label: l.sharePreparing),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.text.titleMedium?.copyWith(color: context.colors.muted));
}
