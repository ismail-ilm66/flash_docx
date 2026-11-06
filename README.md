# Flash Dox — Offline Document Scanner

**Flutter · Dart · OpenCV · Google ML Kit · Android & iOS**

Flash Dox is a cross-platform mobile app that turns phone photos into clean, print-ready documents. You capture or import a page, the app finds the document's edges, corrects perspective and lighting, and exports the result as a PDF, JPG or PNG. Detection, enhancement, OCR and PDF generation all run on the device, with no server, no account and no network needed.

---

## Highlights

- Built a **production-structured Flutter app (~17,500 lines of hand-written Dart)** using **Clean Architecture** across 9 feature modules, with **BLoC** state management, **dependency injection** (`get_it` + `injectable`) and a **pure-Dart domain layer**.
- Implemented an **on-device computer-vision pipeline in OpenCV** covering multi-strategy edge detection, perspective warp, illumination correction, white balance, CLAHE, non-local-means denoising and adaptive thresholding.
- **Ported a Python/NumPy image pipeline to Dart line by line** and backed it with **automated parity tests**. Output matches the reference to within **0.18 grey levels on average**, and the OCR and black-and-white outputs are **pixel-identical**.
- Wrote a **custom long-lived background isolate worker** that runs heavy image and PDF jobs as a serial queue. This keeps the UI at full frame rate and avoids paying the cost of spawning an isolate for every job.
- Handled **48–200 MP camera sensors** without running out of memory: the app **parses JPEG headers directly** to read image size without decoding, then decodes at 1/2 or 1/4 scale only when the target size allows it.
- Designed **non-destructive editing**. Original photos are never modified, every edit is stored as data, and processed images are caches that can be rebuilt at any time.
- Built **native platform integrations**: an Android share-intent receiver in **Kotlin** over a `MethodChannel`, and an iOS **Share Extension** in **Swift**.
- Generated **true-to-size print layouts** for ID cards (ISO ID-1, 85.6 × 54 mm) and passports (ID-3) at 300/600 DPI, with double-sided and single-page PDF output.
- Integrated **AdMob rewarded video** with **UMP/GDPR consent** behind a domain interface, using a fail-open policy so an ad outage never blocks the user.
- Built a **testing and CI setup**: unit, bloc, widget and **golden** tests, a database **migration test**, OpenCV benchmarks, and a **GitHub Actions** pipeline for analysis, tests and an Android build.

---

## Features

| Area | What it does |
|---|---|
| **Capture** | Camera with Document, ID Card (front + back) and Passport modes. Tap-to-focus with an animated focus ring, flash toggle, shutter sound and haptics, and blur/darkness checks on each shot. |
| **Import** | Multi-select from the gallery or Files app, plus images shared *into* the app from WhatsApp, Files and other apps (Android and iOS). |
| **Auto clean-up** | Edge detection, perspective correction, auto-rotate and automatic enhancement, applied to imports as well as camera shots. |
| **Manual adjust** | Drag corners with a magnifier loupe and **magnetic edges** that snap to detected lines and corners. Shape validation keeps the crop a valid convex quad. Rotate, retake, re-run detection. |
| **Filters** | Original, Auto (colour), ID colour, Color boost, Grayscale and B&W print, with brightness and contrast sliders and *apply to all pages*. |
| **Documents** | Multi-page documents with rename, drag-to-reorder, add and delete pages, and a recent-activity feed on Home. |
| **OCR** | Offline text extraction with Google ML Kit, run on a dedicated OCR-optimised render rather than the user's chosen filter. Edit, copy, or share the text as `.txt`. |
| **Export** | PDF / JPG / PNG through the system share sheet or saved to the gallery, in Standard (A4 at 300 DPI) or High (original resolution) quality. |
| **Print layouts** | Cut-ready ID card and passport sheets at real physical size, 1–8 copies, as an image, a double-sided PDF or a one-page PDF. |
| **Settings** | System / Light / Dark theme, scan and export defaults, storage usage, privacy policy, FAQ, rate and share. |

---

## Architecture

```
presentation (pages, widgets, blocs/cubits)
        │
        ▼
domain (entities, repository contracts, use cases)   ← pure Dart, no Flutter imports
        ▲
        │
data (Drift DB, OpenCV, ML Kit, PDF, AdMob implementations)
```

- **Feature-first layout.** Each feature (`documents`, `scanner`, `editor`, `ocr`, `export`, `print_layout`, `rewards`, `settings`, `splash`) has its own `data / domain / presentation` layers.
- **Dependency inversion for every heavy dependency.** Image processing, OCR, PDF building and rewarded ads are interfaces in the domain layer (`ImageProcessor`, `TextRecognizer`, `PdfBuilder`, `RewardGate`) with concrete implementations in data. Each one can be swapped or mocked in tests.
- **Functional error handling.** Repositories return `Either<Failure, T>` (`fpdart`), so failures are values instead of thrown exceptions.
- **Immutable models and sealed states.** `freezed` entities, plus sealed `Idle / Working(progress) / Done / Failed` states for every long-running job.
- **Strategy pattern for scan modes.** A `ScanModeRules` object per mode defines page limits, card sides, target aspect ratio and completion rules, so widgets contain no `if (mode == …)` branches.
- **Declarative navigation.** `go_router` with a `StatefulShellRoute` for the bottom navigation, plus back-navigation guards that stop an unsaved scan from being lost to an accidental back gesture.
- **Build flavors** as separate Dart entry points (`main_dev.dart` / `main_prod.dart`), each with its own ad units and logging.

### State management

| Type | Used for |
|---|---|
| **Bloc** (event-driven) | `ScanSessionBloc` (capture queue), `PageEditorBloc`, `ExportBloc` |
| **Cubit** (simple screens) | Home, Viewer, OCR, Print layout, Settings, Theme, Rewards |

`bloc_concurrency` transformers control how events overlap. Preview renders are debounced and `restartable`, so moving a slider quickly cancels the old render instead of queueing stale ones.

---

## Image-processing engine

The core of the app is an OpenCV pipeline of about 1,200 lines (`features/editor/data/opencv/pipeline.dart`). It is written as small synchronous functions that can be tested in isolation and run inside the background isolate.

### Edge detection
- Builds **three candidate binary maps** for each photo: Canny edges, bright regions (Otsu on LAB lightness) and low-saturation regions (inverse Otsu on HSV saturation). This finds pale cards on dark tables and documents in poor lighting, where edge-only detectors fail.
- Turns contours into quads through a **convex hull → `approxPolyDP` with increasing ε → minimum-area rectangle** fallback. This handles rounded card corners and slightly curled pages.
- Scores candidates on corner angles, area and **aspect-ratio hints** (ID-1 at 1.585, ID-3 at 1.42). In card modes it searches the on-screen guide frame first.
- **Magnetic edges:** Canny + `HoughLinesP`, collinear segment merging and line intersections produce snap targets for manual corner adjustment.

### Enhancement filters
- **Auto:** NLM denoise → gray-world white balance → illumination normalisation (dividing by an estimated paper background, with a floor and a capped blend) → CLAHE on lightness only → slight saturation boost. Text stays crisp, and stamps and photos keep their colour.
- **ID colour:** sharp, true colours with no background whitening, because a card is not white paper.
- **B&W print:** normalise → adaptive threshold with a block size scaled to the image width → median filter, for photocopy-style output.
- **Numerical fidelity:** custom `median` and `percentile` functions reproduce NumPy's definitions exactly, and a half-level bias makes OpenCV's rounding match NumPy's `astype(uint8)` truncation. Without these, the port drifts at each step.

### Quality and performance
- **Encode once.** Every output is JPEG-encoded a single time, and PDFs embed those JPEG bytes directly instead of decoding and re-compressing them.
- **Size tiers.** 1200 px previews, 2000–2480 px Standard exports (area-averaged downscale), and original resolution for High.
- **Pre-shrink before warp.** When the target is much smaller than the source, the image is downscaled with `INTER_AREA` before the perspective warp, so the warp itself never has to downsample.
- **Explicit native memory ownership.** OpenCV `Mat`s live outside the Dart GC. Every function follows a documented ownership rule (never dispose an input, always return a new Mat or the same one), and an *ownership matrix* test checks it.
- **Background capture queue.** The shutter becomes available again right after `takePicture()`. Pages are processed one at a time in the background, and "Done" waits for the queue to drain.

---

## Data and persistence

- **Drift (SQLite)** stores documents, pages and the activity log. A **versioned schema with tested migrations** moves v1 Single/Batch rows into the v2 Document mode.
- **Reactive queries.** Home watches a `Stream<List<ScanDocument>>`, so it updates on its own after any change.
- A **file store** keeps originals byte-for-byte (camera shots are moved, imports copied) and applies EXIF orientation when files are read.
- `shared_preferences` holds user defaults, which the scan and export flows apply.

---

## Platform integration

- **Android:** a Kotlin `MainActivity` receives `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intents (both cold start and `onNewIntent`) and passes file paths to Dart over a `MethodChannel`. A second channel reports free device storage, which drives the camera's low-space warning.
- **iOS:** a Swift **Share Extension** target with an app group, so photos shared from other apps open in Flash Dox.
- **Native splash** (`flutter_native_splash`) hands off to an in-app splash drawn at the same size and position, so there is no visible jump between the two.
- **Native build hook config:** the OpenCV build includes only `imgproc`, `imgcodecs` and `photo`, which keeps the binary small.

---

## Monetisation and privacy

- **Rewarded video (AdMob)** unlocks premium export options for each export.
- **Google UMP consent flow** for EEA/UK users runs before the ads SDK starts.
- **Fail-open policy.** If the device is offline the user gets an "offline" result. If an ad fails to load or there is no fill, the feature is granted anyway. Closing the ad early cancels the unlock. The user is never stuck because of an ad problem.
- Everything else works with no network: no account, no uploads, no analytics on document content.

---

## Design system and UI

- **Theme tokens** and `ThemeExtension`s for full **light and dark** themes, plus a System option. Capture and editing screens stay dark on purpose.
- A **shared widget library of about 20 components** (buttons, dialogs, bottom sheets, segmented pills, sliders, page thumbnails, dashed add-page tiles, empty/error/loading states) used across screens.
- **Custom SVG icon set** and the **Manrope** typeface (400–800 weights).
- **Localisation-ready**, with every string in ARB files compiled to `AppLocalizations`.
- **Golden tests** lock in the shared widgets and the brand mark visually.

---

## Testing and tooling

| Kind | Examples |
|---|---|
| **Unit** | Quad geometry and crop validity, print-layout calculator (mm → px at DPI), scan-mode rules, home sorting, OpenCV module availability |
| **Bloc** | `ScanSessionBloc`, `PageEditorBloc`, `ExportBloc` (with `mocktail`) |
| **Integration-style** | Document repository against an in-memory Drift DB, schema migration v1 → v2, isolate runner behaviour |
| **Image pipeline** | Reference-parity test against Python outputs, edge-detection fixtures with labelled ground-truth corners, print-render output, Mat ownership matrix |
| **Golden** | Shared widget library and brand mark |
| **Benchmarks** | Tagged `bench` suite that times decode / ingest / enhance / export on 12 MP and 16 MP images and writes a before/after visual evidence sheet |

- **22 test files, 90+ test cases**, linted with **`very_good_analysis`** (strict rules).
- **GitHub Actions CI:** code generation → `flutter analyze` → `flutter test` → Android APK build, triggered on demand.
- **Code generation** with `build_runner` for `freezed`, `json_serializable`, `drift` and `injectable`.
- **Python reference tooling** (`tool/reference/`) regenerates the expected outputs for the parity tests.

---

## Tech stack

| Category | Technologies |
|---|---|
| Language / framework | Dart 3.10, Flutter 3.38 |
| Architecture | Clean Architecture, feature-first modules, SOLID, Strategy pattern |
| State management | `flutter_bloc`, `bloc_concurrency` |
| DI / navigation | `get_it`, `injectable`, `go_router` |
| Models / errors | `freezed`, `json_serializable`, `fpdart` (`Either`) |
| Persistence | `drift` (SQLite), `shared_preferences` |
| Computer vision | OpenCV via `opencv_dart` (FFI) |
| Machine learning | Google ML Kit Text Recognition (on-device) |
| Documents | `pdf` (PDF generation), `share_plus`, `gal` |
| Device | `camera`, `image_picker`, `file_picker`, `audioplayers` |
| Native | Kotlin (Android `MethodChannel`), Swift (iOS Share Extension) |
| Monetisation | `google_mobile_ads` (rewarded), Google UMP consent |
| Testing / CI | `flutter_test`, `mocktail`, golden tests, `very_good_analysis`, GitHub Actions |

---

## Project structure

```
lib/
├── app/              # app shell, router, DI, theme tokens, flavors, bootstrap
├── core/             # failures, use-case base, constants, services
│                     # (file store, share, save, isolate runner, share-in)
├── shared/widgets/   # reusable component library
├── l10n/             # ARB strings → generated AppLocalizations
└── features/
    ├── documents/    # Drift DB, repository, Home, Viewer
    ├── scanner/      # camera, scan modes (strategy), import, capture queue
    ├── editor/       # OpenCV pipeline, page rendering, Adjust edges, Enhance
    ├── ocr/          # ML Kit recogniser, extracted-text screen
    ├── export/       # PDF / JPG / PNG export, share sheet
    ├── print_layout/ # real-size ID card and passport sheets
    ├── rewards/      # AdMob rewarded video, consent, unlock dialog
    ├── settings/
    └── splash/
```

---

## Development

The full product plan (screens, flows, domain model) is in `flash_dox_plan.md`.

### Commands

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

### Before a store release

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

### Engine notes (round 3, Nov 2026)

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

### Notes

* Edits are non-destructive: `ScanPage.edits` is the source of truth; processed
  and thumb JPEGs are caches rebuilt by `PageRenderService`.
* All OpenCV / PDF work runs through `IsolateRunner`, a serial queue over
  `compute`, so two renders never overlap.
* `pdf` 3.12 pins `archive < 4.1`; `image` is overridden to 4.5.4 in
  `pubspec.yaml` so `flutter_native_splash` builds. Remove the override once
  `pdf` ≥ 3.13 resolves on your Dart SDK.
