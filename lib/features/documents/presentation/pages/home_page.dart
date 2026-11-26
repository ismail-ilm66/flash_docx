import 'dart:async';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/core/services/share_in_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/cubit/home_cubit.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/features/documents/presentation/widgets/document_menu.dart';
import 'package:flash_dox/features/documents/presentation/widgets/draft_card.dart';
import 'package:flash_dox/features/documents/presentation/widgets/folder_chips.dart';
import 'package:flash_dox/features/documents/presentation/widgets/pick_document_sheet.dart';
import 'package:flash_dox/features/documents/presentation/widgets/tools_row.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/export/presentation/bloc/export_bloc.dart';
import 'package:flash_dox/features/export/presentation/share_sheet.dart';
import 'package:flash_dox/features/photo/presentation/photo_crop_page.dart';
import 'package:flash_dox/features/reduce/presentation/reduce_size_page.dart';
import 'package:flash_dox/features/scanner/data/draft_service.dart';
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

/// Home, round 11 redesign (artboards *HomeV11*, *HomeSelect*,
/// *HomeSearch*): a fixed header (logo · search · settings), then one
/// scrolling list: greeting, the Scan a document card with ID Card ·
/// Passport · Import, Tools, folder pills and the documents. A floating
/// camera button sits bottom right; no bottom navigation.
class _HomeViewState extends State<_HomeView> {
  StreamSubscription<List<String>>? _shareSub;
  bool _importing = false;
  bool _searching = false;
  bool _scrolled = false;
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final shareIn = getIt<ShareInService>();
    unawaited(shareIn.initialShare().then(_onSharedIn));
    _shareSub = shareIn.shares.listen(_onSharedIn);
    _scroll.addListener(() {
      final scrolled = _scroll.hasClients && _scroll.offset > 0;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    LeaveAppGuard.interceptor = null;
    _shareSub?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _onSharedIn(List<String> paths) async {
    if (paths.isEmpty) return;
    await _startImport(paths, copySource: false);
  }

  Future<void> _importFrom({required bool gallery, ToolTarget? tool}) async {
    final svc = getIt<ImportService>();
    final r = gallery ? await svc.fromGallery() : await svc.fromFiles();
    if (!mounted) return;
    await r.fold(
      (f) async {
        if (f is! CancelledFailure) context.showSnack(failureMessage(context, f), error: true);
      },
      (paths) => _startImport(paths, tool: tool),
    );
  }

  Future<void> _startImport(List<String> paths, {bool copySource = true, ToolTarget? tool}) async {
    if (_importing) return;
    setState(() => _importing = true);
    const mode = ScanMode.document;
    final r = await getIt<PreparePages>()(paths, mode: mode, copySource: copySource);
    if (!mounted) return;
    setState(() => _importing = false);
    r.fold(
      (f) => context.showSnack(failureMessage(context, f), error: true),
      (pages) => context.push(Routes.adjust, extra: EditorArgs(pages: pages, mode: mode, tool: tool)),
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

  /// P1-1: search mode (back arrow + field; results right under it, above
  /// the keyboard).
  void _openSearch() {
    setState(() => _searching = true);
    _syncBack();
  }

  void _closeSearch() {
    _searchCtrl.clear();
    context.read<HomeCubit>().search('');
    setState(() => _searching = false);
    _syncBack();
  }

  /// Back leaves search or selection mode first, then (Home) the app.
  void _syncBack() {
    final cubit = context.read<HomeCubit>();
    LeaveAppGuard.interceptor = cubit.state.selecting
        ? cubit.clearSelection
        : _searching
        ? _closeSearch
        : null;
  }

  /// Home › Tools: Passport photo, Sign document, Reduce size, Extract text.
  List<HomeTool> _tools(BuildContext context) {
    final l = context.l10n;
    return [
      HomeTool(icon: AppIcons.portrait, label: l.toolPassportPhoto, onTap: () => startPassportPhoto(context)),
      HomeTool(icon: AppIcons.signature, label: l.toolSign, onTap: () => _runTool(context, ToolTarget.sign)),
      HomeTool(icon: AppIcons.shrink, label: l.toolReduceSize, onTap: () => startReduceSize(context)),
      HomeTool(icon: AppIcons.text, label: l.toolExtractText, onTap: () => _runTool(context, ToolTarget.extractText)),
    ];
  }

  /// A Home tool (P1-4): pick a document, or scan / import a new one that
  /// goes straight to the tool after Done.
  Future<void> _runTool(BuildContext context, ToolTarget tool) async {
    final pick = await showPickDocumentSheet(context, tool: tool);
    if (pick == null || !context.mounted) return;
    switch (pick) {
      case PickedDocument(:final document):
        await openTool(context, tool, document);
      case PickScanNew():
        await context.push(
          Routes.camera,
          extra: CameraArgs(
            mode: ScanMode.document,
            tool: tool,
            hint: tool == ToolTarget.extractText ? CameraHint.extractText : null,
          ),
        );
      case PickFromPhotos():
        await _importFrom(gallery: true, tool: tool);
    }
  }

  void _scan(BuildContext context, ScanMode mode) => context.push(Routes.camera, extra: CameraArgs(mode: mode));

  Future<void> _onMore(BuildContext context, ScanDocument doc) async {
    final cubit = context.read<HomeCubit>();
    final action = await showDocumentMenu(context, doc);
    if (action == null || !context.mounted) return;
    switch (action) {
      case DocumentMenuAction.rename:
        await renameDocumentFlow(context, doc, (t) => cubit.rename(doc.id, t));
      case DocumentMenuAction.moveToFolder:
        await moveToFolderFlow(context, doc, (f) => cubit.moveTo(doc.id, f));
      case DocumentMenuAction.share:
        await showShareSheet(context, doc);
      case DocumentMenuAction.delete:
        await deleteDocumentFlow(context, doc, () => cubit.delete(doc.id));
    }
  }

  // ---- several documents at once (round 10, P1-5; round 11, P0-1–P0-3) ----

  Future<void> _deleteSelected(BuildContext context) async {
    final l = context.l10n;
    final c = context.colors;
    final cubit = context.read<HomeCubit>();
    final n = cubit.state.selected.length;
    final ok = await AppDialog.confirm(
      context,
      title: l.homeDeleteManyTitle(n),
      body: l.homeDeleteManyBody,
      confirmLabel: l.commonDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final ids = cubit.hideSelected();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    // P0-3: closes by itself after 5 s (a snackbar with an action stays
    // until dismissed unless told otherwise), floats above the camera
    // button, Undo in amber.
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            content: Text(l.homeDeletedMany(ids.length)),
            duration: const Duration(seconds: 5),
            persist: false,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, 96),
            action: SnackBarAction(label: l.commonUndo, textColor: c.accent, onPressed: () {}),
          ),
        )
        .closed;
    // The files go only once Undo is no longer possible.
    if (reason == SnackBarClosedReason.action) {
      cubit.undoDelete(ids);
    } else {
      await cubit.commitDelete(ids);
    }
  }

  Future<void> _shareSelected(BuildContext context) async {
    final cubit = context.read<HomeCubit>();
    final docs = cubit.state.selectedDocuments;
    cubit.clearSelection();
    setState(() => _importing = true);
    final prefs = getIt<PrefsService>();
    final r = await getIt<ExportDocument>().shareMany(docs, (d) => ExportBloc.defaultsFor(prefs, d));
    if (!mounted) return;
    setState(() => _importing = false);
    r.fold(
      (f) {
        if (f is! CancelledFailure && context.mounted) context.showSnack(failureMessage(context, f), error: true);
      },
      (_) {},
    );
  }

  Future<void> _moveSelected(BuildContext context) async {
    final l = context.l10n;
    final cubit = context.read<HomeCubit>();
    final picked = await showChoiceSheet<DocFolder>(
      context,
      title: l.menuMoveToFolder,
      values: FolderChips.order,
      labelOf: (f) => folderLabel(context, f),
    );
    if (picked == null || !context.mounted) return;
    final err = await cubit.moveSelected(picked);
    if (!context.mounted) return;
    context.showSnack(err != null ? l.errorGeneric : l.movedToFolder(folderLabel(context, picked)), error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<HomeCubit, HomeState>(
      listenWhen: (a, b) => a.selecting != b.selecting,
      listener: (context, s) => _syncBack(),
      builder: (context, s) {
        final cubit = context.read<HomeCubit>();
        final showEmpty = !s.loading && s.all.isEmpty && s.search.isEmpty;
        final plain = !_searching && !s.selecting;
        final bottomPad = MediaQuery.paddingOf(context).bottom;

        final list = <Widget>[
          if (!_searching) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, 0),
              sliver: SliverList.list(
                children: [
                  // Round 11: one line, nothing under it.
                  FitText(
                    _greeting(context),
                    maxLines: 1,
                    textAlign: TextAlign.start,
                    style: context.text.headlineMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: Space.x4),
                  DraftCard(drafts: getIt<DraftService>()),
                  _ScanCard(onTap: () => _scan(context, ScanMode.document)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final (i, a) in [
                        (AppIcons.idCard, l.homeIdCard, () => _scan(context, ScanMode.idCard)),
                        (AppIcons.passport, l.modePassport, () => _scan(context, ScanMode.passport)),
                        (AppIcons.gallery, l.homeImport, _pickImportSource),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: Space.x2),
                        Expanded(child: _QuickAction(icon: a.$1, label: a.$2, onTap: a.$3)),
                      ],
                    ],
                  ),
                  const SizedBox(height: Space.x5),
                  ToolsRow(tools: _tools(context)),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, Space.x5, Space.x3, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.homeRecent, style: context.text.titleLarge?.copyWith(fontSize: 17)),
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
            if (!showEmpty && s.all.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: Space.x2),
                  child: FolderChips(counts: s.counts, selected: s.folder, onSelected: cubit.setFolder),
                ),
              ),
          ] else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, Space.x2),
                child: Text(
                  l.homeResultsCount(s.documents.length),
                  style: context.text.labelLarge?.copyWith(color: c.muted, fontWeight: FontWeight.w700),
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
          else if (!s.loading && s.documents.isEmpty && !_searching)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x8),
                child: s.folder != null && s.all.isNotEmpty
                    ? EmptyState(icon: AppIcons.files, title: l.folderEmpty(folderLabel(context, s.folder!)))
                    : EmptyState(icon: AppIcons.search, title: l.homeNoResults),
              ),
            )
          else
            SliverPadding(
              // Room under the last row for the camera button / action bar.
              padding: const EdgeInsets.fromLTRB(Space.x5, 0, Space.x2, 96),
              sliver: SliverList.builder(
                itemCount: s.documents.length,
                itemBuilder: (context, i) {
                  final d = s.documents[i];
                  return DocumentTile(
                    document: d,
                    selecting: s.selecting,
                    selected: s.selected.contains(d.id),
                    onTap: s.selecting ? () => cubit.toggleSelected(d.id) : () => context.push(Routes.viewer(d.id)),
                    onLongPress: s.selecting || _searching ? null : () => cubit.startSelection(d.id),
                    onMore: () => _onMore(context, d),
                  );
                },
              ),
            ),
        ];

        return AppScaffold(
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    if (s.selecting)
                      _SelectionBar(
                        count: s.selected.length,
                        all: s.documents.isNotEmpty && s.selected.length == s.documents.length,
                        onClose: cubit.clearSelection,
                        onSelectAll: cubit.selectAll,
                        onDeselectAll: cubit.selectNone,
                      )
                    else if (_searching)
                      _SearchBar(controller: _searchCtrl, onChanged: cubit.search, onBack: _closeSearch)
                    else
                      _Header(
                        divider: _scrolled,
                        onSearch: _openSearch,
                        onSettings: () => context.push(Routes.settings),
                      ),
                    Expanded(
                      child: CustomScrollView(
                        controller: _scroll,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: list,
                      ),
                    ),
                  ],
                ),
                if (plain)
                  Positioned(
                    right: 20,
                    bottom: 24 + bottomPad,
                    child: ScanFab(onPressed: () => _scan(context, ScanMode.document)),
                  ),
                if (s.selecting)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SelectionActionBar(
                      enabled: s.selected.isNotEmpty,
                      actions: [
                        SelectionAction(AppIcons.delete, l.commonDelete, () => _deleteSelected(context), danger: true),
                        SelectionAction(AppIcons.share, l.viewerShare, () => _shareSelected(context)),
                        SelectionAction(AppIcons.files, l.viewerMove, () => _moveSelected(context)),
                      ],
                    ),
                  ),
                if (_importing) ProgressOverlay(label: l.sharePreparing),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "Good morning" before 12:00, "Good afternoon" until 17:00, then "Good
  /// evening".
  String _greeting(BuildContext context) {
    final l = context.l10n;
    final h = DateTime.now().hour;
    return h < 12
        ? l.homeGreetingMorning
        : h < 17
        ? l.homeGreetingAfternoon
        : l.homeGreetingEvening;
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

/// Logo + FLASH DOX, search and settings on the right. Gets the page
/// background and a 1 px divider once the list scrolls under it (P1-2).
class _Header extends StatelessWidget {
  const _Header({required this.divider, required this.onSearch, required this.onSettings});

  final bool divider;
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: divider ? c.border : Colors.transparent)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x5, Space.x3, Space.x2, Space.x2),
        child: Row(
          children: [
            const BrandMark(),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l.appName.toUpperCase(),
                  maxLines: 1,
                  style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
            ),
            IconButton(
              tooltip: l.homeSearchHint,
              onPressed: onSearch,
              icon: AppIcon(AppIcons.search, size: 22, color: c.text),
            ),
            IconButton(
              tooltip: l.navSettings,
              onPressed: onSettings,
              icon: Icon(Icons.settings_outlined, size: 23, color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// P1-1 (artboard *HomeSearch*): back arrow + search field.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged, required this.onBack});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.bg, border: Border(bottom: BorderSide(color: c.border))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x1, Space.x2, Space.x4, Space.x2),
        child: Row(
          children: [
            IconButton(
              tooltip: l.commonBack,
              onPressed: onBack,
              icon: AppIcon(AppIcons.back, size: 22, color: c.text),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.homeSearchHint,
                  prefixIcon: AppIcon(AppIcons.search, size: 20, color: c.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selection mode's top bar (P0-2, artboard *HomeSelect*): a light amber
/// band with ✕, "3 selected" and an outlined "Select all" / "Deselect all".
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.all,
    required this.onClose,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  final int count;
  final bool all;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final band = c.isDark ? const Color(0xFF2A2410) : const Color(0xFFFFF3D1);
    final ink = c.isDark ? const Color(0xFFF3F3F1) : const Color(0xFF15171A);
    return ColoredBox(
      color: band,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x1, Space.x2, Space.x4, Space.x2),
        child: Row(
          children: [
            IconButton(
              tooltip: l.commonClose,
              onPressed: onClose,
              icon: AppIcon(AppIcons.close, size: 22, color: ink),
            ),
            const SizedBox(width: Space.x1),
            Expanded(
              child: FitText(
                l.homeSelectedCount(count),
                maxLines: 1,
                textAlign: TextAlign.start,
                style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: ink),
              ),
            ),
            const SizedBox(width: Space.x2),
            OutlinedButton.icon(
              onPressed: all ? onDeselectAll : onSelectAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                side: BorderSide(color: ink.withValues(alpha: 0.6)),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                textStyle: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              icon: Icon(all ? Icons.check_box_outline_blank_rounded : Icons.check_box_outlined, size: 18, color: ink),
              label: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(all ? l.homeDeselectAll : l.homeSelectAll, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big amber "Scan a document" card with the page illustration on the
/// right; tapping anywhere opens the camera in Document mode.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onTap});

  final VoidCallback onTap;

  static const _ink = Color(0xFF15171A);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Semantics(
      button: true,
      label: l.homeScanTitle,
      excludeSemantics: true,
      child: Material(
        color: c.accent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x5, Space.x5, Space.x3, Space.x5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.homeScanTitle,
                        style: context.text.headlineSmall?.copyWith(fontSize: 21, fontWeight: FontWeight.w800, color: _ink, height: 1.15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.homeScanSubtitle,
                        style: context.text.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: _ink.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x3),
                const SizedBox(width: 84, height: 96, child: CustomPaint(painter: _ScanIllustration())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page with text lines, scan corners and a scan line (vector).
class _ScanIllustration extends CustomPainter {
  const _ScanIllustration();

  @override
  void paint(Canvas canvas, Size size) {
    const ink = Color(0xFF15171A);
    final page = Rect.fromLTWH(size.width * 0.14, size.height * 0.1, size.width * 0.72, size.height * 0.8);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(page.shift(const Offset(0, 3)), const Radius.circular(6)),
        Paint()..color = ink.withValues(alpha: 0.18),
      )
      ..drawRRect(RRect.fromRectAndRadius(page, const Radius.circular(6)), Paint()..color = Colors.white);
    final line = Paint()
      ..color = ink.withValues(alpha: 0.28)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final left = page.left + page.width * 0.16;
    for (final (i, w) in [0.55, 0.68, 0.62, 0.68, 0.4].indexed) {
      final y = page.top + page.height * (0.2 + i * 0.15);
      canvas.drawLine(Offset(left, y), Offset(left + page.width * w, y), line);
    }
    // Scan corners just outside the page.
    final corner = Paint()
      ..color = ink
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = page.inflate(5);
    const k = 12.0;
    for (final (o, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(o, o + Offset(k * dx, 0), corner)
        ..drawLine(o, o + Offset(0, k * dy), corner);
    }
    // The scan line.
    final y = page.top + page.height * 0.58;
    canvas.drawLine(
      Offset(r.left + 2, y),
      Offset(r.right - 2, y),
      Paint()
        ..color = const Color(0xFFFF8A00)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScanIllustration old) => false;
}

/// ID Card · Passport · Import: icon and label on one line, 48 dp high.
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final AppIcons icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(icon, size: 18, color: c.accentText),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FitText(
                      label,
                      maxLines: 1,
                      style: context.text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
