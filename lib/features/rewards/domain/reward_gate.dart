enum PremiumFeature { highQualityExport, pngExport, allPagesText, moreCopies }

enum RewardResult { granted, cancelled, offline }

/// Rewarded ads are off for the first release: every [PremiumFeature] is
/// free and no unlock UI appears. To bring ads back, restore
/// `AdMobRewardGate` (see docs/release-checklist.md) and set this to true.
const bool rewardedAdsEnabled = false;

/// Features available before any video is watched.
const Set<PremiumFeature> unlockedByDefault =
    rewardedAdsEnabled ? <PremiumFeature>{} : {...PremiumFeature.values};

abstract interface class RewardGate {
  /// Consent (UMP) + SDK init. Called once at start-up; safe to call again.
  Future<void> initialize();

  /// Starts loading a rewarded ad so it's ready when the user taps unlock.
  void preload();

  /// Shows the rewarded video. Resolves `granted` on reward, on no-fill or
  /// load error (fail-open), `cancelled` if the user closes early and
  /// `offline` when there's no connection.
  Future<RewardResult> unlock(PremiumFeature feature);
}
