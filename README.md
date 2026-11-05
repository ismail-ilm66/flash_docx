# Flash Dox

Offline document scanner for Android and iOS. Capture or import → auto clean-up →
manual adjust → view → share as images or PDF. See `flash_dox_plan.md` for the
full product plan; this file covers how to work on the code.

## Stack

Flutter 3.38 · Clean Architecture · `flutter_bloc` · feature-first ·
`get_it` + `injectable` · `go_router` · `freezed` · `fpdart` · `drift` ·
OpenCV (`opencv_dart`) · ML Kit text recognition · `pdf` · `google_mobile_ads`.

```
lib/
├── app/            # app shell, router, DI, theme tokens, flavor, bootstrap
├── core/           # failures, use case base, constants, services (files, share, save, isolate queue)
├── shared/widgets/ # §12 widget library (used on 2+ screens)
├── l10n/           # app_en.arb → generated AppLocalizations
└── features/
    ├── documents/  # Drift DB, repository, Home, Viewer
    ├── scanner/    # camera, modes (strategy), import, scan session
    ├── editor/     # OpenCV pipeline, PageEditorBloc, Adjust edges, Enhance
    ├── ocr/        # ML Kit, extracted text screen
    ├── export/     # PDF/JPG/PNG export, share sheet
    ├── print_layout/ # ID card / passport sheets at real size
    ├── rewards/    # AdMob rewarded video + UMP consent, unlock dialog
    └── settings/
```

## Commands

```sh
flutter pub get
dart run build_runner build --force-jit   # freezed / json / drift / injectable
flutter gen-l10n                           # after editing lib/l10n/app_en.arb
flutter analyze && flutter test
flutter test --update-goldens test/shared  # after intentional UI changes

flutter run -t lib/main_dev.dart           # dev flavor: test ad units, bloc logs
flutter build appbundle -t lib/main_prod.dart
flutter build apk --split-per-abi -t lib/main_prod.dart
```

`--force-jit` is required for `build_runner` on this toolchain: `sqlite3` ships a
native build hook that the AOT builder compile does not support.

Flavors are Dart entry points (`main_dev.dart` / `main_prod.dart`), not native
product flavors, so no Xcode scheme work is needed.

## Before a store release

| Item | Where |
|---|---|
| App ID | `com.flashdox.app` (placeholder) in `android/app/build.gradle.kts`, `ios/Runner.xcodeproj`, `core/constants/app_info.dart` |
| AdMob app IDs | `AndroidManifest.xml`, `ios/Runner/Info.plist` (currently Google test IDs) |
| Rewarded unit IDs | `features/rewards/data/ad_ids.dart` (prod IDs still `XXXX`; dev + unset prod both use test units) |
| Privacy / FAQ / store URLs | `core/constants/app_info.dart` |
| Crashlytics | add `google-services.json` / `GoogleService-Info.plist`, `firebase_core` + `firebase_crashlytics`, hook in `app/bootstrap.dart` |
| App icon | default Flutter icon still in place |
| Design icons | done: the canvas's stroke set is in `assets/icons/`; entries still on Material fallbacks in `shared/widgets/app_icons.dart` have no `asset:` |
| Splash | the in-app splash is drawn from `assets/images/brand_mark.svg`; `assets/splash/splash_icon.png` (native splash) is still a placeholder; replace it and rerun `dart run flutter_native_splash:create` |
| Android signing | `buildTypes.release` still signs with the debug key |
| iOS share-in | needs a Share Extension target in Xcode; Android share-in is done natively in `MainActivity.kt` |

## Engine notes (round 3, Nov 2026)

* **Reference port.** Detection, warp and filters are a line-by-line port of
  the owner's `tool/reference/flashdox_reference.py`
  (`features/editor/data/opencv/pipeline.dart`). `python3
  tool/reference/dump_reference.py` writes the reference's outputs for every
  photo in `test/fixtures/edges/`; `reference_parity_test.dart` checks the
  Dart port against them (mean difference ≤ 0.2 levels; OCR and B&W print
  identical). Keep the two in step when either changes.
* **Originals are never touched.** Camera shots are moved, imports copied,
  byte for byte; EXIF is applied whenever they are read. Previews are
  1200 px, Standard exports 2000 px, High is the original resolution; every
  output is encoded once and PDFs embed those JPEGs as they are.
* **Capture.** The shutter does feedback → `takePicture()` → queue. A
  background queue (`ScanSessionBloc`) processes one page at a time and
  "Done" waits for it. Logs: `[capture] takePicture … ms; shutter ready again
  after … ms`, `[ingest] W×H (MP, MB) … sharpness … brightness …`.
* **Thresholds to calibrate** on real phones: `CaptureChecks.blurThreshold`
  and `darkThreshold` (provisional; every capture logs its values).
* **Edge fixtures.** `test/fixtures/edges/*.jpg` + corner JSON (README
  there). The 26-of-30 acceptance test runs once 30 fixtures exist; until then
  it reports the count.
* **OpenCV modules:** `hooks.user_defines.dartcv4.include_modules` in
  pubspec — `photo` is required (non-local-means denoise).
* **Modes:** Document / ID Card / Passport. DB schema v2 migrates the old
  Single / Batch rows to Document.
* **iOS share-in** needs a one-time Xcode step: see `ios/ShareExtension/README.md`.
* **Benchmarks / evidence:** `flutter test test/bench --tags bench
  --run-skipped` prints timings and writes `docs/round3/results_dart.jpg`.

## Notes

* Edits are non-destructive: `ScanPage.edits` is the source of truth; processed
  and thumb JPEGs are caches rebuilt by `PageRenderService`.
* All OpenCV / PDF work runs through `IsolateRunner`, a serial queue over
  `compute`, so two renders never overlap.
* `pdf` 3.12 pins `archive < 4.1`; `image` is overridden to 4.5.4 in
  `pubspec.yaml` so `flutter_native_splash` builds. Remove the override once
  `pdf` ≥ 3.13 resolves on your Dart SDK.
