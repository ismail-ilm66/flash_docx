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
  bool _searching = false;
  final _searchCtrl = TextEditingController();

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
    _searchCtrl.dispose();
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

  Future<void> _pickImportSource() async {
    final l = context.l10n;
    final gallery = await AppBottomSheet.show<bool>(
      context,
      builder: (ctx) => AppBottomSheet(
        title: l.homeImport,
        padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x4),
        child: Column(
          children: [
            SheetAction(
              label: l.homeImportGallery,
              leading: const AppIcon(AppIcons.gallery),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            SheetAction(
              label: l.homeImportFiles,
              leading: const AppIcon(AppIcons.files),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (gallery == null || !mounted) return;
    await _importFrom(gallery: gallery);
  }

  Future<void> _pickSort(BuildContext context, HomeSort current) async {
    final cubit = context.read<HomeCubit>();
    final picked = await showChoiceSheet<HomeSort>(
      context,
      title: context.l10n.homeSortBy,
      values: HomeSort.values,
      selected: current,
      labelOf: (v) => _sortLabel(context, v),
    );
    if (picked != null) cubit.setSort(picked);
  }

  void _toggleSearch(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchCtrl.clear();
      cubit.search('');
    }
  }

  void _scan(BuildContext context, ScanMode? mode) =>
      context.push(Routes.camera, extra: CameraArgs(mode: mode));

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
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    _Header(searching: _searching, onSearch: () => _toggleSearch(context)),
                    AnimatedSize(
                      duration: Motion.normal,
                      curve: Curves.easeOutCubic,
                      child: !_searching
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(Space.x5, Space.x1, Space.x5, Space.x2),
                              child: TextField(
                                controller: _searchCtrl,
                                autofocus: true,
                                onChanged: context.read<HomeCubit>().search,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: l.homeSearchHint,
                                  prefixIcon: AppIcon(AppIcons.search, size: 20, color: c.muted),
                                ),
                              ),
                            ),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, 0),
                            sliver: SliverList.list(
                              children: [
                                Text(
                                  l.homeHeadline,
                                  style: context.text.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: Space.x5),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final (i, tile) in [
                                      QuickActionTile(icon: AppIcons.document, label: l.homeDocument, onTap: () => _scan(context, null)),
                                      QuickActionTile(icon: AppIcons.idCard, label: l.modeIdCard, onTap: () => _scan(context, ScanMode.idCard)),
                                      QuickActionTile(icon: AppIcons.passport, label: l.modePassport, onTap: () => _scan(context, ScanMode.passport)),
                                      QuickActionTile(icon: AppIcons.gallery, label: l.homeImport, onTap: _pickImportSource),
                                    ].indexed) ...[
                                      if (i > 0) const SizedBox(width: 10),
                                      Expanded(child: tile),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(Space.x5, Space.x5, Space.x3, 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l.homeRecentActivity,
                                      style: context.text.titleLarge?.copyWith(fontSize: 17),
                                    ),
                                  ),
                                  if (!showEmpty)
                                    TextButton(
                                      onPressed: () => _pickSort(context, s.sort),
                                      style: TextButton.styleFrom(
                                        foregroundColor: c.muted,
                                        minimumSize: const Size(Sizes.tap, Sizes.tap),
                                        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                                        textStyle: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_sortLabel(context, s.sort)),
                                          const SizedBox(width: Space.x1),
                                          AppIcon(AppIcons.chevronDown, size: 16, color: c.muted),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (showEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: EmptyState(title: l.homeEmptyTitle, body: l.homeEmptyBody),
                            )
                          else if (s.failure != null)
                            SliverFillRemaining(hasScrollBody: false, child: ErrorView(failure: s.failure))
                          else if (!s.loading && s.documents.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: EmptyState(icon: AppIcons.search, title: l.homeNoResults),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(Space.x5, 0, Space.x2, Space.x6),
                              sliver: SliverList.builder(
                                itemCount: s.documents.length,
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
                    ),
                  ],
                ),
                if (_importing) ProgressOverlay(label: l.sharePreparing),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _sortLabel(BuildContext context, HomeSort s) {
  final l = context.l10n;
  return switch (s) {
    HomeSort.latest => l.homeSortLatest,
    HomeSort.oldest => l.homeSortOldest,
    HomeSort.name => l.homeSortName,
  };
}

/// Brand mark + wordmark, with the search toggle on the right.
class _Header extends StatelessWidget {
  const _Header({required this.searching, required this.onSearch});

  final bool searching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x5, Space.x4, Space.x3, Space.x2),
      child: Row(
        children: [
          BrandMark(color: c.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                l.appName.toUpperCase(),
                style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            ),
          ),
          IconButton(
            tooltip: searching ? l.commonClose : l.homeSearchHint,
            onPressed: onSearch,
            icon: AppIcon(searching ? AppIcons.close : AppIcons.search, size: 22, color: c.text),
          ),
        ],
      ),
    );
  }
}
