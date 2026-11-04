enum PremiumFeature { highQualityExport, pngExport, allPagesText, moreCopies }

enum RewardResult { granted, cancelled, offline }

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
