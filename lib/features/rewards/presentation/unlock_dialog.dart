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

String _unlockBody(BuildContext context, PremiumFeature f) {
  final l = context.l10n;
  final why = switch (f) {
    PremiumFeature.highQualityExport => l.unlockBodyHighQuality,
    PremiumFeature.pngExport => l.unlockBodyPng,
    PremiumFeature.allPagesText => l.unlockBodyAllPagesText,
    PremiumFeature.moreCopies => l.unlockBodyMoreCopies,
  };
  return '$why ${l.unlockFreeNote}';
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
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: Space.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 326),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 28, Space.x6, Space.x5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon(AppIcons.play, size: 28, color: c.onAccent),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.unlockFeatureTitle(premiumFeatureLabel(context, feature)),
                    textAlign: TextAlign.center,
                    style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _unlockBody(context, feature),
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(height: 1.5, color: c.muted),
                  ),
                  const SizedBox(height: 14),
                  if (offline)
                    Container(
                      padding: const EdgeInsets.all(Space.x3),
                      decoration: BoxDecoration(color: c.isDark ? c.surface : c.surface2, borderRadius: Radii.mdR),
                      child: Row(
                        children: [
                          AppIcon(AppIcons.offline, size: 18, color: c.muted),
                          const SizedBox(width: Space.x3),
                          Expanded(child: Text(l.unlockOffline, style: context.text.bodySmall)),
                        ],
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(AppIcons.online, size: 14, color: c.muted),
                        const SizedBox(width: 6),
                        Text(
                          l.unlockNeedsInternet,
                          style: context.text.labelMedium?.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: loading ? l.unlockLoading : l.unlockWatch,
                    loading: loading,
                    onPressed: offline ? null : () => context.read<RewardCubit>().unlock(feature),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: c.text,
                        minimumSize: const Size(Sizes.tap, 48),
                        shape: const StadiumBorder(),
                        textStyle: context.text.labelLarge?.copyWith(fontSize: 15),
                      ),
                      child: Text(l.unlockNotNow),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
