import 'dart:async';

import 'package:flash_dox/app/flavor.dart';
import 'package:flash_dox/core/services/connectivity_service.dart';
import 'package:flash_dox/core/services/prefs_service.dart';
import 'package:flash_dox/features/rewards/data/ad_ids.dart';
import 'package:flash_dox/features/rewards/domain/reward_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:injectable/injectable.dart';

/// Rewarded video via AdMob with UMP consent.
///
/// Policy (from the plan): offline → `offline`; load failure / no fill →
/// `granted` (fail-open); user closes early → `cancelled`.
@LazySingleton(as: RewardGate)
class AdMobRewardGate implements RewardGate {
  AdMobRewardGate(this._connectivity, this._prefs);

  final ConnectivityService _connectivity;
  final PrefsService _prefs;

  RewardedAd? _loaded;
  Future<RewardedAd?>? _loading;
  bool _sdkReady = false;

  static const _loadTimeout = Duration(seconds: 8);

  /// Runs the UMP consent flow (no-op outside EEA/UK) and initialises the SDK.
  Future<void> initialize() async {
    if (_sdkReady) return;
    try {
      await _gatherConsent();
    } catch (e) {
      debugPrint('consent: $e');
    }
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
    } catch (e) {
      debugPrint('ads init: $e');
    }
  }

  Future<void> _gatherConsent() async {
    final completer = Completer<void>();
    final params = ConsentRequestParameters(
      consentDebugSettings: FlavorConfig.isDev
          ? ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyDisabled)
          : null,
    );
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('consent form: ${error.message}');
          if (!completer.isCompleted) completer.complete();
        });
      },
      (error) {
        debugPrint('consent update: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    await _prefs.setConsentDone(true);
  }

  @override
  void preload() {
    if (_loaded != null || _loading != null) return;
    _loading = _load().whenComplete(() => _loading = null);
  }

  Future<RewardedAd?> _load() async {
    await initialize();
    if (!_sdkReady) return null;
    final completer = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loaded = ad;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (err) {
          debugPrint('rewarded load failed: ${err.code} ${err.message}');
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () => null);
  }

  @override
  Future<RewardResult> unlock(PremiumFeature feature) async {
    if (!await _connectivity.isOnline) return RewardResult.offline;

    var ad = _loaded;
    ad ??= await (_loading ?? _load());
    _loaded = null;
    if (ad == null) {
      // No fill / error → grant anyway (keeps the UX good and is allowed).
      return RewardResult.granted;
    }

    final completer = Completer<RewardResult>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!completer.isCompleted) {
          completer.complete(earned ? RewardResult.granted : RewardResult.cancelled);
        }
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        a.dispose();
        debugPrint('rewarded show failed: ${err.message}');
        if (!completer.isCompleted) completer.complete(RewardResult.granted);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
    } catch (e) {
      debugPrint('rewarded show threw: $e');
      if (!completer.isCompleted) completer.complete(RewardResult.granted);
    }
    final r = await completer.future;
    preload(); // Have the next one ready.
    return r;
  }
}
