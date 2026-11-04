import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/editor/presentation/widgets/quad_editor.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class AdjustEdgesPage extends StatelessWidget {
  const AdjustEdgesPage({required this.args, super.key});

  final EditorArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PageEditorBloc>(param1: args)..add(EditorStarted(args)),
      child: const _AdjustView(),
    );
  }
}

class _AdjustView extends StatelessWidget {
  const _AdjustView();

  Future<void> _retake(BuildContext context) async {
    final path = await context.push<String>(
      Routes.camera,
      extra: const CameraArgs(retake: true),
    );
    if (path != null && context.mounted) {
      context.read<PageEditorBloc>().add(EditorPageRetaken(path));
    }
  }

  Future<void> _deletePage(BuildContext context, PageEditorState s) async {
    final l = context.l10n;
    final ok = await AppDialog.confirm(
      context,
      title: l.deletePageTitle,
      body: l.deletePageBody,
      confirmLabel: l.commonDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final bloc = context.read<PageEditorBloc>();
    bloc.add(const EditorPageDeleted());
    if (s.pages.length <= 1) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return BlocBuilder<PageEditorBloc, PageEditorState>(
      builder: (context, s) {
        final bloc = context.read<PageEditorBloc>();
        final page = s.current;
        final base = s.basePreview;
        final multi = s.pages.length > 1;
        return AppScaffold(
          forceDark: true,
          topBar: AppTopBar(
            title: l.adjustTitle,
            subtitle: multi && page != null ? l.pageOfTotal(s.index + 1, s.pages.length) : l.adjustHint,
            actions: [
              TopBarTextAction(
                label: l.adjustNext,
                onPressed: page == null ? null : () => context.push(Routes.enhance, extra: bloc),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(Space.x6, Space.x8, Space.x6, multi ? 56 : Space.x8),
                          child: page == null || base == null
                              ? (s.status == EditorStatus.failed
                                  ? ErrorView(failure: s.failure)
                                  : const Center(child: CircularProgressIndicator()))
                              : RotatedBox(
                                  quarterTurns: page.edits.normalizedTurns,
                                  child: QuadEditor(
                                    key: ValueKey(page.id),
                                    imagePath: base,
                                    quad: page.edits.crop ?? Quad.full(),
                                    onCornerMoved: (i, p) => bloc.add(EditorCornerMoved(i, p)),
                                    onDragEnd: () => bloc.add(const EditorCornerDragEnded()),
                                  ),
                                ),
                        ),
                      ),
                      if (multi)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: Space.x1,
                          child: Center(
                            child: PageDots(
                              count: s.pages.length,
                              index: s.index,
                              onSelect: (i) => bloc.add(EditorPageSelected(i)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x1, 10, Space.x1, 18),
                  child: _Toolbar(
                    onAuto: () => bloc.add(const EditorAutoEdgesRequested()),
                    onRotateLeft: () => bloc.add(const EditorRotated(clockwise: false)),
                    onRotateRight: () => bloc.add(const EditorRotated(clockwise: true)),
                    onRetake: () => _retake(context),
                    onDelete: () => _deletePage(context, s),
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onAuto,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onRetake,
    required this.onDelete,
  });

  final VoidCallback onAuto;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onRetake;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Row(
      children: [
        Expanded(child: ToolbarAction(icon: AppIcons.rotateLeft, label: l.adjustRotateLeft, onPressed: onRotateLeft)),
        Expanded(child: ToolbarAction(icon: AppIcons.rotateRight, label: l.adjustRotateRight, onPressed: onRotateRight)),
        Expanded(child: ToolbarAction(icon: AppIcons.autoEdges, label: l.adjustAuto, onPressed: onAuto, active: true)),
        Expanded(child: ToolbarAction(icon: AppIcons.retake, label: l.adjustRetake, onPressed: onRetake)),
        Expanded(child: ToolbarAction(icon: AppIcons.delete, label: l.adjustDeletePage, onPressed: onDelete, destructive: true)),
      ],
    );
  }
}
