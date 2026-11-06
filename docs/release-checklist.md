# Release checklist

Placeholders to replace before a store release.

| Item | Where |
|---|---|
| App ID | `com.flashdox.app` (placeholder) in `android/app/build.gradle.kts`, `ios/Runner.xcodeproj`, `core/constants/app_info.dart` |
| Privacy / FAQ / store URLs | `core/constants/app_info.dart` |
| Crashlytics | add `google-services.json` / `GoogleService-Info.plist`, `firebase_core` + `firebase_crashlytics`, hook in `app/bootstrap.dart` |
| App icon | default Flutter icon still in place |
| Design icons | done: the canvas's stroke set is in `assets/icons/`; entries still on Material fallbacks in `shared/widgets/app_icons.dart` have no `asset:` |
| Splash | the in-app splash is drawn from `assets/images/brand_mark.svg`; `assets/splash/splash_icon.png` (native splash) is still a placeholder; replace it and rerun `dart run flutter_native_splash:create` |
| Android signing | `buildTypes.release` still signs with the debug key |
| iOS share-in | needs a Share Extension target in Xcode; Android share-in is done natively in `MainActivity.kt` |

## Rewarded ads (off for v1)

v1 ships without the ads SDK: `rewardedAdsEnabled` in
`features/rewards/domain/reward_gate.dart` is `false`, every premium option
starts unlocked, and `UnlockAllRewardGate` is registered. To bring ads back:

1. `git show fe25c65:lib/features/rewards/data/admob_reward_gate.dart` (and
   `ad_ids.dart`) to restore the AdMob gate; delete `unlock_all_reward_gate.dart`.
2. Re-add `google_mobile_ads` to `pubspec.yaml`, the AdMob `APPLICATION_ID`
   meta-data to `AndroidManifest.xml`, `GADApplicationIdentifier` +
   `SKAdNetworkItems` to `ios/Runner/Info.plist`, and the
   `-keep class com.google.android.gms.ads.**` ProGuard rule.
3. Set `rewardedAdsEnabled = true`, fill the prod unit IDs, run build_runner.
4. Add a UMP privacy-options entry in Settings
   (`ConsentForm.showPrivacyOptionsForm`); it was never built.
5. Update Play Console: Ads = yes, Advertising ID declaration, Data safety
   (device IDs, approximate location, app interactions, diagnostics), and the
   privacy policy.

