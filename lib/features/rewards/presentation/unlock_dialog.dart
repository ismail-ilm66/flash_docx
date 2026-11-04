import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flash_dox/features/rewards/presentation/reward_cubit.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

String premiumFeatureLabel(BuildContext context, PremiumFeature f) {
  final l = context.l10n;
  return switch (f) {
    PremiumFeature.highQualityExport => l.featureHighQuality,
    PremiumFeature.pngExport => l.featurePng,
    PremiumFeature.allPagesText => l.featureAllPagesText,
    PremiumFeature.moreCopies => l.featureMoreCopies,
  };
}

/// Shows the "Unlock with video" dialog. Resolves true when the feature was
/// granted (video watched, or ad unavailable → fail-open).
Future<bool> showUnlockDialog(BuildContext context, PremiumFeature feature) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => getIt<RewardCubit>()..preload(),
      child: _UnlockDialog(feature: feature),
    ),
  );
  return r ?? false;
}

class _UnlockDialog extends StatelessWidget {
  const _UnlockDialog({required this.feature});
  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return BlocConsumer<RewardCubit, RewardState>(
      listener: (context, s) {
        if (s.status == RewardStatus.granted) Navigator.of(context).pop(true);
        if (s.status == RewardStatus.cancelled) Navigator.of(context).pop(false);
      },
      builder: (context, s) {
        final offline = s.status == RewardStatus.offline;
        final loading = s.status == RewardStatus.loading;
        return AppDialog(
          title: l.unlockTitle,
          body: l.unlockBody(premiumFeatureLabel(context, feature)),
          content: offline
              ? Container(
                  padding: const EdgeInsets.all(Space.x3),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: Radii.mdR),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.offline, color: c.muted),
                      const SizedBox(width: Space.x3),
                      Expanded(child: Text(l.unlockOffline, style: context.text.bodySmall)),
                    ],
                  ),
                )
              : Center(child: AppIcon(AppIcons.video, size: 48, color: c.accent)),
          primaryLabel: loading ? l.unlockLoading : l.unlockWatch,
          primaryLoading: loading,
          onPrimary: offline ? null : () => context.read<RewardCubit>().unlock(feature),
          secondaryLabel: l.unlockNotNow,
          onSecondary: () => Navigator.of(context).pop(false),
        );
      },
    );
  }
}
