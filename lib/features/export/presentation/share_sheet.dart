import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/presentation/bloc/export_bloc.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/features/rewards/presentation/unlock_dialog.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Share / save bottom sheet (§11). Preloads a rewarded ad on open.
Future<void> showShareSheet(BuildContext context, ScanDocument doc) {
  getIt<RewardGate>().preload();
  return AppBottomSheet.show<void>(
    context,
    builder: (_) => BlocProvider(
      create: (_) => getIt<ExportBloc>(param1: doc),
      child: const _ShareSheet(),
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet();

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<ExportBloc>().state.options.fileName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _update(ExportOptions o) => context.read<ExportBloc>().add(ExportOptionsChanged(o));

  Future<void> _go(ExportTarget target) async {
    final bloc = context.read<ExportBloc>();
    _update(bloc.state.options.copyWith(fileName: _name.text));
    final needed = bloc.state.requiredUnlock;
    if (needed != null) {
      final ok = await showUnlockDialog(context, needed);
      if (!ok || !mounted) return;
      bloc.add(ExportFeatureUnlocked(needed));
    }
    bloc.add(ExportRequested(target));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<ExportBloc, ExportState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        final st = s.status;
        if (st is ExportDone) {
          if (st.target == ExportTarget.saveToPhone) context.showSnack(l.shareSaved);
          Navigator.of(context).pop();
        } else if (st is ExportFailed) {
          final f = st.failure;
          context.showSnack(
            f is PermissionFailure ? l.errorPermission : failureMessage(context, f),
            error: true,
          );
        }
      },
      builder: (context, s) {
        final o = s.options;
        final working = s.status is ExportWorking;
        final progress = s.status is ExportWorking ? (s.status as ExportWorking).progress : null;
        return AppBottomSheet(
          title: l.shareTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(l.shareFormat),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  for (final f in ExportFormat.values)
                    OptionChip(
                      label: switch (f) {
                        ExportFormat.pdf => l.sharePdf,
                        ExportFormat.jpg => l.shareJpg,
                        ExportFormat.png => l.sharePng,
                      },
                      selected: o.format == f,
                      gated: f == ExportFormat.png && !s.unlocked.contains(PremiumFeature.pngExport),
                      onTap: () => _update(o.copyWith(format: f)),
                    ),
                ],
              ),
              const SizedBox(height: Space.x4),
              _Label(l.shareQuality),
              Wrap(
                spacing: Space.x2,
                runSpacing: Space.x2,
                children: [
                  OptionChip(
                    label: l.shareQualityStandard,
                    selected: o.quality == ExportQuality.standard,
                    onTap: () => _update(o.copyWith(quality: ExportQuality.standard)),
                  ),
                  OptionChip(
                    label: l.shareQualityHigh,
                    selected: o.quality == ExportQuality.high,
                    gated: !s.unlocked.contains(PremiumFeature.highQualityExport),
                    onTap: () => _update(o.copyWith(quality: ExportQuality.high)),
                  ),
                ],
              ),
              if (!o.isImage) ...[
                const SizedBox(height: Space.x4),
                _Label(l.sharePageSize),
                SegmentedPills<PdfPageSize>(
                  values: PdfPageSize.values,
                  selected: o.pageSize,
                  labelOf: (p) => switch (p) {
                    PdfPageSize.a4 => l.sharePageA4,
                    PdfPageSize.letter => l.sharePageLetter,
                    PdfPageSize.fit => l.sharePageFit,
                  },
                  onChanged: (p) => _update(o.copyWith(pageSize: p)),
                ),
              ],
              const SizedBox(height: Space.x4),
              _Label(l.shareFileName),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(suffixText: '.${o.extension}'),
              ),
              const SizedBox(height: Space.x5),
              if (working) ...[
                LinearProgressIndicator(value: progress == 0 ? null : progress, borderRadius: Radii.pillR),
                const SizedBox(height: Space.x2),
                Text(l.sharePreparing, style: context.text.bodySmall?.copyWith(color: c.muted)),
                const SizedBox(height: Space.x3),
              ],
              PrimaryButton(
                label: l.shareButton,
                icon: AppIcons.share,
                loading: working,
                onPressed: () => _go(ExportTarget.share),
              ),
              const SizedBox(height: Space.x2),
              SecondaryButton(
                label: l.shareSaveToPhone,
                icon: AppIcons.save,
                onPressed: working ? null : () => _go(ExportTarget.saveToPhone),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.x2),
        child: Text(text, style: context.text.labelMedium?.copyWith(color: context.colors.muted)),
      );
}
