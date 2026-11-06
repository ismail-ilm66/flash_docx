import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:injectable/injectable.dart';

/// v1 gate: no ads SDK, every feature is granted. With [rewardedAdsEnabled]
/// off nothing calls [unlock]; it grants anyway so a stray call can't block.
@LazySingleton(as: RewardGate)
class UnlockAllRewardGate implements RewardGate {
  @override
  Future<void> initialize() async {}

  @override
  void preload() {}

  @override
  Future<RewardResult> unlock(PremiumFeature feature) async => RewardResult.granted;
}
