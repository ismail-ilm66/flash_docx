import 'dart:io';

import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/editor/presentation/widgets/page_strip.dart';
import 'package:flash_dox/features/ocr/presentation/cubit/ocr_cubit.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/features/rewards/presentation/unlock_dialog.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ExtractedTextPage extends StatelessWidget {
  const ExtractedTextPage({required this.documentId, super.key, this.initialPageId});

  final String documentId;
  final String? initialPageId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<OcrCubit>(param1: documentId, param2: initialPageId),
      child: const _OcrView(),
    );
  }
}

class _OcrView extends StatefulWidget {
  const _OcrView();

  @override
  State<_OcrView> createState() => _OcrViewState();
}

class _OcrViewState extends State<_OcrView> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<OcrCubit>().separator = context.l10n.ocrPageSeparator;
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    if (!mounted) return;
    context.showSnack(context.l10n.ocrCopied);
    await context.read<OcrCubit>().logCopied();
  }

  Future<void> _cut() async {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final hasSel = sel.isValid && !sel.isCollapsed;
    final cutText = hasSel ? sel.textInside(text) : text;
    await Clipboard.setData(ClipboardData(text: cutText));
    _ctrl.text = hasSel ? sel.textBefore(text) + sel.textAfter(text) : '';
    if (mounted) context.read<OcrCubit>().setText(_ctrl.text);
  }

  Future<void> _shareTxt() async {
    final doc = context.read<OcrCubit>().state.document;
    final name = '${doc?.title ?? 'text'}.txt';
    final f = File(getIt<FileStore>().exportPath(name));
    await f.writeAsString(_ctrl.text);
    await getIt<ShareService>().shareFiles([f], subject: doc?.title);
  }

  Future<void> _selectScope(OcrScope s) async {
    final cubit = context.read<OcrCubit>();
    if (s == OcrScope.allPages && !cubit.state.allPagesUnlocked) {
      final ok = await showUnlockDialog(context, PremiumFeature.allPagesText);
      if (!ok) return;
      cubit.unlockAllPages();
    }
    cubit.setScope(s);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<OcrCubit, OcrState>(
      listenWhen: (a, b) => a.text != b.text,
      listener: (context, s) {
        if (_ctrl.text != s.text) _ctrl.text = s.text;
      },
      builder: (context, s) {
        final doc = s.document;
        final pages = doc?.sortedPages ?? const [];
        final st = s.status;
        final working = st is OcrWorking;
        final multi = pages.length > 1;
        final pageIndex = pages.isEmpty ? 0 : pages.indexWhere((p) => p.id == s.page?.id).clamp(0, pages.length - 1);
        final cubit = context.read<OcrCubit>();
        void goTo(int i) => cubit.selectPage(pages[i].id);
        final empty = s.text.isEmpty;

        return AppScaffold(
          topBar: AppTopBar(title: l.ocrTitle),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (multi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x5, Space.x1, Space.x5, 0),
                  child: SegmentedPills<OcrScope>(
                    values: OcrScope.values,
                    selected: s.scope,
                    labelOf: (v) => v == OcrScope.page ? l.ocrThisPage : l.ocrAllPages,
                    badgeOf: (v) => v == OcrScope.allPages && !s.allPagesUnlocked ? const VideoBadge(compact: true, size: 16) : null,
                    onChanged: _selectScope,
                  ),
                ),
              if (multi && s.scope == OcrScope.page)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: PageStrip(
                    pages: pages,
                    index: pageIndex,
                    size: 44,
                    onSelect: goTo,
                    pathOf: (p) => p.thumbPath ?? p.displayPath,
                    cacheKeyOf: (p) => p.thumbPath,
                  ),
                ),
              if (working)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, 0),
                  child: Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: st.total > 1 ? st.done / st.total : null)),
                      const SizedBox(width: Space.x2),
                      Text(
                        st.total > 1 ? '${l.ocrWorking} ${st.done}/${st.total}' : l.ocrWorking,
                        style: context.text.bodySmall?.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: st is OcrFailed
                    ? ErrorView(failure: st.failure, onRetry: cubit.run)
                    : Container(
                        margin: EdgeInsets.fromLTRB(Space.x5, multi ? Space.x1 : Space.x2, Space.x5, 0),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: Radii.lgR,
                          border: Border.all(color: c.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 18),
                        child: TextField(
                          controller: _ctrl,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: context.text.bodyLarge?.copyWith(fontSize: 15, height: 1.7),
                          onChanged: cubit.setText,
                          decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: st is OcrDone && empty ? l.ocrEmpty : null,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, 10, Space.x5, 0),
                child: Text(l.ocrHint, style: context.text.bodySmall?.copyWith(color: c.muted)),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x5, 14, Space.x5, Space.x5),
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: l.ocrCut,
                          icon: AppIcons.cut,
                          height: 48,
                          dense: true,
                          filled: true,
                          onPressed: empty ? null : _cut,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          label: l.ocrShareTxt,
                          excludeSemantics: true,
                          button: true,
                          child: SecondaryButton(
                            label: l.ocrTxt,
                            icon: AppIcons.share,
                            height: 48,
                            dense: true,
                            filled: true,
                            onPressed: empty ? null : _shareTxt,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: l.ocrCopyAll,
                          icon: AppIcons.copy,
                          height: 48,
                          dense: true,
                          onPressed: empty ? null : _copyAll,
                        ),
                      ),
                    ],
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
