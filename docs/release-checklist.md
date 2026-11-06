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

## Build (round 4, checked 6 Nov 2026)

- **Bundle:** `flutter build appbundle --release -t lib/main_prod.dart --obfuscate --split-debug-info=build/symbols`.
  Keep `build/symbols` for every uploaded version: stack traces can't be read without it.
- **SDK levels:** `targetSdk` comes from Flutter 3.38.9's default, which is 36; `minSdk = 24`.
- **Permissions:** the merged release manifest has only `CAMERA` (plus the app's own
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`). `INTERNET` is removed (owner question 6).
- **Logs:** `debugPrint` is a no-op in release (`app/bootstrap.dart`); profile builds keep the
  `[perf]` / `[ingest]` / `[shrink]` / `[smart]` lines for timing runs.
- **OpenCV modules:** `imgproc`, `imgcodecs`, `photo` (`pubspec.yaml` hook config).
- **Size:** an arm64 release APK is 92.9 MB because plugin native libraries ship all ABIs
  (OpenCV 10.5 MB, ML Kit OCR 10.6 MB, Flutter 10.6 MB, app 7.8 MB per arm64 alone).
  Play's per-ABI split of the App Bundle sends a phone only its own ABI, about 45 MB
  uncompressed for arm64. Check the real download size in Play Console › App size.
- **Still the owner's:** upload keystore + `key.properties` (release still signs with the debug
  key), final package name, privacy policy URL, store graphics.

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

