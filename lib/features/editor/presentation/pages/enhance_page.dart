import 'dart:io';

import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/widgets/page_strip.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Filters + brightness/contrast. Shares the [PageEditorBloc] created by
/// Adjust edges, so edits on both screens are one in-memory session.
class EnhancePage extends StatelessWidget {
  const EnhancePage({required this.bloc, super.key});

  final PageEditorBloc bloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: bloc..add(const EditorPreviewRequested(forEnhance: true)),
      child: const _EnhanceView(),
    );
  }
}

class _EnhanceView extends StatefulWidget {
  const _EnhanceView();

  @override
  State<_EnhanceView> createState() => _EnhanceViewState();
}

class _EnhanceViewState extends State<_EnhanceView> {
  bool _comparing = false;
  int _lastAppliedTick = 0;

  // Local slider values so the thumb follows the finger at 60 fps while the
  // bloc debounces the actual render.
  double? _brightness;
  double? _contrast;

  void _onSaved(BuildContext context, PageEditorState s) {
    final id = s.savedDocumentId!;
    final args = s.args;
    if (args.isNewDocument) {
      context.go(Routes.home);
      context.push(Routes.viewer(id));
    } else {
      // Pop Enhance and Adjust edges back to the viewer.
      context
        ..pop()
        ..pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<PageEditorBloc, PageEditorState>(
      listenWhen: (a, b) =>
          a.status != b.status ||
          a.appliedToAllTick != b.appliedToAllTick ||
          a.index != b.index,
      listener: (context, s) {
        if (s.status == EditorStatus.saved) _onSaved(context, s);
        if (s.status == EditorStatus.failed && s.failure != null) {
          context.showSnack(failureMessage(context, s.failure), error: true);
        }
        if (s.appliedToAllTick != _lastAppliedTick) {
          _lastAppliedTick = s.appliedToAllTick;
          context.showSnack(l.enhanceAppliedAll);
        }
        setState(() { _brightness = null; _contrast = null; });
      },
      builder: (context, s) {
        final bloc = context.read<PageEditorBloc>();
        final page = s.current;
        final edits = s.edits;
        final preview = _comparing ? s.basePreview : (s.enhancePreview ?? s.basePreview);
        final multi = s.pages.length > 1;
        final saving = s.status == EditorStatus.saving;

        return AppScaffold(
          forceDark: true,
          topBar: AppTopBar(
            title: l.enhanceTitle,
            subtitle: multi && page != null ? l.viewerPageOf(s.index + 1, s.pages.length) : null,
            actions: [
              TextButton(
                onPressed: () => bloc.add(const EditorLookReset()),
                child: Text(l.enhanceReset),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x3),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (preview != null)
                            GestureDetector(
                              onLongPressStart: (_) => setState(() => _comparing = true),
                              onLongPressEnd: (_) => setState(() => _comparing = false),
                              child: _comparing
                                  ? RotatedBox(
                                      quarterTurns: edits.normalizedTurns,
                                      child: Image.file(File(preview), gaplessPlayback: true),
                                    )
                                  : Image.file(
                                      File(preview),
                                      key: ValueKey(preview),
                                      gaplessPlayback: true,
                                    ),
                            )
                          else
                            const CircularProgressIndicator(),
                          if (s.rendering && !_comparing)
                            Positioned(
                              top: Space.x2,
                              right: Space.x2,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                              ),
                            ),
                          Positioned(
                            bottom: Space.x2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: Radii.pillR,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon(AppIcons.compare, size: 14, color: c.muted),
                                  const SizedBox(width: Space.x1),
                                  Text(
                                    _comparing ? l.filterOriginal : l.enhanceHoldToCompare,
                                    style: context.text.labelSmall?.copyWith(color: c.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (multi)
                    PageStrip(
                      pages: s.pages,
                      index: s.index,
                      onSelect: (i) => bloc.add(EditorPageSelected(i)),
                      pathOf: (p) => s.basePreviews[p.id] ?? p.originalPath,
                    ),
                  // Filters
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                      itemCount: FilterType.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: Space.x2),
                      itemBuilder: (context, i) {
                        final f = FilterType.values[i];
                        return OptionChip(
                          label: filterLabel(context, f),
                          selected: edits.filter == f,
                          onTap: () => bloc.add(EditorFilterChanged(f)),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
                    child: Column(
                      children: [
                        LabeledSlider(
                          label: l.enhanceBrightness,
                          value: _brightness ?? edits.brightness,
                          onChanged: (v) {
                            setState(() => _brightness = v);
                            bloc.add(EditorBrightnessChanged(v));
                          },
                          onChangeEnd: (_) => setState(() => _brightness = null),
                        ),
                        LabeledSlider(
                          label: l.enhanceContrast,
                          value: _contrast ?? edits.contrast,
                          onChanged: (v) {
                            setState(() => _contrast = v);
                            bloc.add(EditorContrastChanged(v));
                          },
                          onChangeEnd: (_) => setState(() => _contrast = null),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          if (multi) ...[
                            Expanded(
                              child: SecondaryButton(
                                label: l.enhanceApplyAll,
                                icon: AppIcons.pages,
                                onPressed: saving ? null : () => bloc.add(const EditorApplyLookToAll()),
                              ),
                            ),
                            const SizedBox(width: Space.x3),
                          ],
                          Expanded(
                            child: PrimaryButton(
                              label: l.enhanceDone,
                              loading: saving,
                              onPressed: page == null ? null : () => bloc.add(const EditorSaveRequested()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (saving) ProgressOverlay(label: l.sharePreparing),
            ],
          ),
        );
      },
    );
  }
}
