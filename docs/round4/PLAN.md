# Flash Dox: Round 4 plan

Plan for `flash_dox_fix_list_v4.md` (6 Nov 2026). Release target: **Mon 9 Nov**.

- **Sources:** the fix list v4, `flash_dox_plan.md` v3 §20 (new features), the reference pipeline `flashdox_reference.py`, and the "Flash Dox App Design" canvas.
- **Design files:** every artboard was downloaded on 6 Nov into [`docs/round4/design/`](design/) (index below).
- **Code state:** checked against `main` at `fe25c65`, plus the uncommitted work in the tree (see Step 0).

---

## Step 0: before any fix (Sat, first 30 min)

The tree has uncommitted work that already covers most of **P1-3 (remove ads)** and a night-mode splash. It includes:
- `google_mobile_ads` removed from `pubspec.yaml`
- the AdMob `<meta-data>` removed
- `NoAdsRewardGate`
- `rewardedAdsEnabled = false`
- `night_mode_service.dart`
- dark/light native splash backgrounds

1. Finish and commit it as its own commit ("P1-3: remove ads") after the checks in P1-3 below. Every later fix then starts from a clean tree.
2. Then work in this order, one commit per item, so any item can be dropped from the 9 Nov build without untangling the others.

---

## Design files (downloaded 6 Nov)

| Artboard | File | Changed this round |
|---|---|---|
| Camera | `Camera.dc.html` | **Updated:** full-screen preview, floating bars, 3 modes, Import button, "Done" under the stack |
| Enhance | `Enhance.dc.html` | **Updated:** big preview, zoom pill, 6 filters, Adjust · Reset · All N pages row |
| Home | `Home.dc.html` (+ `HomeLight`) | **Updated:** Tools 2 × 2, folder chips, folder in the meta line |
| Document viewer | `Viewer.dc.html` (+ `ViewerLight`) | Smart-name banner, **Sign** in the bottom bar |
| Share sheet | `Export.dc.html` (+ `ExportLight`) | **Max file size** row ("Under 500 KB"); quality notes "Smaller file · for sharing" / "Best for printing" |
| Settings | `Settings.dc.html` (+ `SettingsLight`) | Magnetic edges, Shutter sound, Text recognition, My signature, Image quality rows |
| Max file size | `FileSize.dc.html` | **New** |
| My signature | `SignatureCreate.dc.html` | **New** |
| Sign a document | `SignaturePlace.dc.html` | **New** |
| Passport photo · crop | `PassportPhoto.dc.html` | **New** |
| Passport photo · print sheet | `PassportSheet.dc.html` | **New** |
| Urdu text · download | `TextUrdu.dc.html` | **New** (v1.1, kept for later) |
| Logo options | `Logos.dc.html` | Reference only |
| Splash, Adjust edges, Extracted text, ID print, Unlock | `Main`, `Crop`, `Text`, `IdPrint`, `Unlock` (+ light) | Unchanged (Unlock is no longer used, P1-3) |

Each file is the artboard's complete source. Open it in a browser next to the app while building, or read it for exact sizes and colours.

---

## Saturday 7 Nov: P0s, P1-1, P1-2, P1-3, P1-5, P1-6

### P0-1 Photo orientation (EXIF): root cause of 4 bugs

**Today**
- Ingest (`PreparePages` → `ImageProcessor.ingest`) keeps the original byte-for-byte. It relies on OpenCV's `imread` to apply EXIF whenever the file is read: `pipeline.dart: readUpright`, and the `IMREAD_REDUCED_*` fast paths at lines 33–39 and 1124.
- The owner's bugs show this isn't reliable on the phones, so some or all reads come back sideways.
- The camera also calls `lockCaptureOrientation(DeviceOrientation.portraitUp)` (`camera_page.dart:131`), so a photo taken with the phone held landscape is saved as portrait.

**Fix**
1. **Bake once, in our own code.** Add `core/utils/exif_orientation.dart`. It reads only the JPEG APP1 orientation tag (the first 64 KB of the file), so no full decode and no new package.
   - At ingest, if the tag isn't 1: decode with `IMREAD_COLOR | IMREAD_IGNORE_ORIENTATION`, apply the tag's rotate/flip (all 8 cases), write the upright JPEG (q95) as the page's `originalPath`, and drop the tag.
   - If the tag is 1 or missing, keep the bytes as they are. This keeps round 3's "original untouched" rule wherever possible.
2. **Every later read** adds `IMREAD_IGNORE_ORIENTATION`, including the reduced-size reads and the `imageSize` probe in `opencv_image_processor.dart:351`. Then no image can be rotated twice, whatever the OpenCV build does.
3. **Camera:** remove `lockCaptureOrientation`. Keep the camera UI portrait-locked with `SystemChrome.setPreferredOrientations`. The photo then carries the device's orientation, and step 1 bakes it in.
4. **ID / Passport auto-orientation**, at the end of `ingest` for card modes:
   - After the warp, if the card is portrait, rotate it 90° to landscape.
   - Pick 0° or 180°: run ML Kit on a 640 px copy both ways (on the main isolate, since ML Kit is a platform channel) and keep the one with more recognised characters. If they're equal, keep 0.
   - Store the result in `PageEdits.quarterTurns`, so the user can still rotate by hand.
5. **Guide-frame search area** (guide + 20% margin): map it into the **upright** image size, after step 1. Today it's mapped against the header size. Same file as the P1-2 mapping: `scanner/presentation/widgets/preview_geometry.dart`.

**Tests**
- Fixture JPEGs with EXIF orientation 1, 3, 6 and 8 (generated in the test with an "up" marker drawn on them). After ingest the marker is at the top for all four. The detected quad is the same as for the already-upright image.
- Golden check of the 8-copy double-sided PDF: render sheet 1 and sheet 2 to images and assert the marker is upright on both.

**Acceptance (owner's phone):** the fix list's three cases. A page held portrait and landscape, a CNIC front/back held portrait and landscape, and the 8-copy PDF. Each must be upright on every screen and in all 3 print outputs.

### P0-2 ID mode is blurry

**Today:** tap-to-focus, focus mode and a blur check all exist from round 3. The blur check measures the **whole photo** (`capture_checks.dart`). There's no zoom.

**Fix**
1. **1.5× zoom** in ID and Passport modes. Call `setZoomLevel(min(1.5, maxZoom))` when the mode opens, and reset to 1× for Document.
   - *14 Nov 2026:* lowered to **1.2×** (`_cardZoom` in `camera_page.dart`). At 1.5× users had to hold the phone too far from the card. The zoom is now also applied again after the app resumes and after a lens flip (it used to stay at 1× there).
2. **Focus on the frame:**
   - When the mode opens and after every tap, set the focus and exposure points to the guide-frame centre.
   - On shutter: refocus on the frame centre, wait 400 ms (the camera plugin has no focus-done callback), then `takePicture()`.
   - Keep the shutter disabled during the wait, so a double tap can't take two photos.
3. **Blur check on the card crop:** `ingest` returns the Laplacian variance of the **warped card at 1000 px wide**. Below the threshold, show "Card looks blurry — Retake / Keep" (the existing notice banner, new copy).
   - Calibrate the threshold on `flash_dox_reference/test_photos` plus 3 deliberately blurry shots, and store it in `capture_checks.dart`.
4. **Hint** under the frame: "Fit the card in the frame · move back if it's blurry".
5. **ID colour filter:** diff `pipeline.dart: idColorFilter` against the reference `filter_id_color` (and its `_denoise(min_h, max_h)` cap), and port the lower noise cap. Re-run `tool/` evidence generation on the test photos and commit the comparison image to `docs/round4/`.

**Acceptance:** CNIC small print readable in the 300 DPI print PDF on the Mate 10 Lite plus one other phone. This needs the owner's phones.

### P0-3 Retake keeps the mode and side

**Today:** `adjust_edges_page.dart:39` pushes `CameraArgs(retake: true)`, and `camera_page.dart:56` forces `ScanMode.document` for retakes.

**Fix**
- `CameraArgs` gets `retakeSide`. Adjust passes `mode: args.mode` and `retakeSide: page.side`.
- The camera opens in that mode with that side's frame and label ("Back side"), takes one photo and pops with its path.
- `EditorPageRetaken` already replaces the page in place and keeps `side`. Also pass the guide fallback quad, and keep `index` on that page.

**Test:** a bloc test where retaking page 2 of an ID scan keeps its side, index and card aspect.

### P0-4 Slow loading in Enhance, viewer and Share; never show the raw photo

**Today**
- A single long-lived worker isolate already exists (`core/services/isolate_runner.dart`) and jobs pass file paths, so items 2 and 6 of the fix list are mostly done.
- The worker runs jobs strictly **one at a time**, so a slider preview waits behind a background export or cache warm-up.
- Where the raw photo shows:
  - Enhance falls back to `basePreview` (the uncropped upright original) while rendering (`enhance_page.dart:83`).
  - The viewer shows `displayPath = processedPath ?? originalPath` (`scan_page.dart:42`), so the raw original appears whenever the cache is missing.

**Fix**
1. **Placeholder chain:** last rendered preview → fast **warp-only 600 px** (no filter, about 50 ms) → filtered **1200 px**.
   - Add `ScanPage.previewPath(...)` / a `PreviewCache` lookup and remove every `?? originalPath` fallback in UI code.
   - Grep `displayPath` and `originalPath` under `presentation/` and replace each one.
2. **`PreviewCache`:** disk plus an in-memory LRU, keyed by `(pageId, editsHash, size)`, in `editor/data/services/`. Enhance and the viewer read from it first.
3. **Worker priorities:**
   - `IsolateRunner.run(..., priority: interactive | background)` with an interactive lane that jumps the queue.
   - A `CancelToken`, so a preview request that's been superseded is dropped before it starts.
   - Exports and cache warm-up use the background lane.
4. **Filter strip:** one job renders all 6 filters on a 160 px warped copy, once per page, cached.
5. **Sliders:** preview size 1600 → **1200 px** (`RenderPx.previewLongEdge`). The 80 ms debounce is already in place; the latest request cancels older ones (point 3).
6. **Share sheet:**
   - When the sheet opens, the `ExportBloc` starts building the default export (Standard PDF) into temp, showing "Preparing… 2/3 pages".
   - Changing page size or format reuses the page JPEGs already rendered; only a quality change re-renders.
   - Tapping Share uses the ready file.
7. Add `[perf]` debug log lines (open→first image, filter→image, share ready) so the owner can read the Mate 10 Lite timings.

**Acceptance (Mate 10 Lite, owner):** Enhance shows an image in under 0.5 s, a filter change in under 0.8 s, and a 3-page Standard PDF is ready in under 3 s. The raw photo never appears.

### P0-5 Zoom in the viewer (and Enhance)

**Today:** the viewer is a `PageView` of `InteractiveViewer`s (`viewer_page.dart:146–155`). Pinch and page-swipe fight each other, and the zoomed image clips.

**Fix:** one shared widget, `shared/widgets/zoomable_pages.dart`.
- At 1×, swiping changes page. Above 1×, the page view gets `NeverScrollableScrollPhysics`.
- Double-tap toggles 1× ↔ 2.5× at the tap point. Pinch range 1×–5×, snapping back to 1× when released below it.
- `boundaryMargin` sized to the image, so every corner is reachable. Clipping only on the viewport.
- Changing page resets the zoom.
- Built on `InteractiveViewer` + `TransformationController`, so no new dependency. `photo_view` is the fallback if the gesture handling gets messy (see question 2).
- Used in the viewer and Enhance (P1-1). The zoom pill (− / 100% / +) drives the same controller.

> "Share preview" in the fix list: the Share sheet has no page preview of its own today (it opens over the viewer). See question 7.

**Test:** a widget test that pinches to 3×, checks a swipe doesn't change page, double-taps back to 1×, then checks a swipe does change page.

### P1-1 Enhance redesign (artboard *Enhance*, updated)

**Layout**
- **Top bar:** back · "Enhance / Page 2 of 3" · **Done**.
- **Preview:** fills the screen on `#16181B`, using `ZoomablePages` (P0-5). Page dots at the top (swipe for other pages). Zoom pill bottom-left, **Hold to compare** bottom-right.
- **Bottom bar** `#1A1C20`:
  - Filter thumbnails: Original · Auto · **ID colour** · Color boost · Grayscale · B&W print, scrollable, 52 × 64. They're real 160 px renders from P0-4, not swatches. Labels 10–11 sp, up to 2 lines, never cut off.
  - Then one row (`1fr 1fr 1.6fr`): **Adjust** · **Reset** · **All N pages** switch pill.
- **Adjust** opens a small panel above the bar with the Brightness / Contrast sliders. Tapping Adjust again, or the preview, closes it.

**Rules**
- **Reset** puts this page's filter and sliders back to the mode default, 0 and 0, and leaves the crop alone. With All pages on, it resets every page. It's enabled only when something differs from the default. (Which default? See question 1.)
- **All pages is ON by default** for a new scan. Today it's a local `_applyAll = false` (`enhance_page.dart:41`). Move it into `PageEditorState` so it survives page changes, defaulting to on.

**Always-dark bug.** The light-mode white panel happens because Enhance reads `context.colors` from the context **above** `AppScaffold(forceDark: true)`'s `Theme`, so it gets the light palette.
- Fix: apply the forced dark theme at the **route** level (`app_router.dart` wraps the Camera, Adjust and Enhance pages in `Theme(data: AppTheme.dark)`), and remove `forceDark` from `AppScaffold`.
- That fixes the same bug on Camera and Adjust edges. Check them in light mode afterwards.

### P1-2 Camera: full-screen preview (artboard *Camera*, updated)

**Today:** a 4:3 preview well between solid top and bottom bars (`preview_well.dart`, `camera_overlay.dart`).

**Changes**
- **Preview:** fills the whole screen with `BoxFit.cover` inside `ClipRect`, under a transparent status bar (edge-to-edge).
- **Top fade** (96 px, black 60% → 0): ✕ · "Document · 3 pages" · flash pill (black 45%).
- **Bottom fade** (250 px, transparent → 78%):
  - Mode pills: **Document · ID Card · Passport** (already 3 modes).
  - Then the controls row: **Import** button (56 px, icon + "Import", opens the Photos / Files sheet) · 84 px shutter · page stack with the count badge and a **"Done"** label.
- **Hint chip:** "Hold steady · edges are found automatically" (Document), or the P0-2 copy (ID / Passport).
- Capture stays full-resolution 4:3. The photo shows more at the sides than the screen; auto-crop removes it.
- **Guide-frame mapping:** screen → photo through the cover-crop transform, in `preview_geometry.dart`. Extend its tests to cover-crop on 19.5:9 and 16:9 screens. It feeds P0-1 step 5 and the detection fallback.
- This replaces round-3 P1-5's 4:3 well. `preview_well.dart` goes away.

### P1-3 Remove ads completely (mostly done; see Step 0)

Remaining checks before the commit:
- **Gate name:** the fix list calls it `UnlockAllRewardGate`, the code has `NoAdsRewardGate`. Rename it to match the list and the plan (a one-line DI change).
- **No video UI anywhere:** grep `VideoBadge`, `showUnlockDialog`, `unlockTitle` and `requiredUnlock`. Each must be unreachable or hidden while `rewardedAdsEnabled` is false. Then delete the Unlock dialog route, or keep it behind the flag.
- **iOS:** confirm `GADApplicationIdentifier` and `SKAdNetworkItems` are gone from `Info.plist` (it's in the uncommitted diff), and no `-keep … gms.ads` ProGuard rule is left.
- **Permissions:** build release and inspect the **merged** manifest (`build/app/intermediates/merged_manifests/release/AndroidManifest.xml`) for `AD_ID`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_EXTERNAL_STORAGE` and `INTERNET`. Remove each unwanted one with `tools:node="remove"`.
  - The Play checklist says **only CAMERA**. `INTERNET` and `ACCESS_NETWORK_STATE` are only there for ads and the offline check (`connectivity_service.dart`). Remove both, and `connectivity_plus` if nothing else uses it (see question 6).

### P1-5 No cut-off text

- **Shorter labels:**
  - Adjust toolbar: "Rotate left/right" → ⟲ "Left" / ⟳ "Right", and "Auto edges" → "Auto".
  - Settings and the Share sheet: use the artboard copy ("Smaller file · for sharing", "Best for printing").
- **Allow 2 lines** (`maxLines: 2`, `softWrap`, centred) in `ToolbarAction`, `QuickActionTile`, the Tools tiles, the filter labels, `SegmentedPills` (already 2 lines) and the `OptionCard` subtitle.
- **Viewer Share button:** label in `FittedBox(fit: BoxFit.scaleDown)`, so it never truncates. Keep the button the full width of its column.
- **Test, the part that keeps this from coming back:** `test/ui/large_font_test.dart` pumps each screen's chrome with `TextScaler.linear(2.0)` (about Android's largest font) at 360 × 740. It fails on any `RenderFlex` overflow, and on any `RenderParagraph` with `didExceedMaxLines` where the label has an ellipsis. It covers Home, Camera overlay, Adjust toolbar, Enhance bar, viewer bar, Share sheet, Print, Settings and Tools.

### P1-6 Viewer details

- **Page counter:** a small chip ("1 / 2", 26 px, `c.chip`), centred under the page, not a full-width bar.
- **Processed pages only:** covered by P0-4 point 1, since the viewer never falls back to `originalPath`.
- **Bottom bar** (from P1-4):
  - Documents: Edit · Text · **Sign** · Share
  - ID / Passport: Edit · Text · Print · Share, with Sign in the ⋮ menu

**Saturday evening:** owner test build (`flutter build apk --release -t lib/main_prod.dart`, while the debug signing key is still in place).

---

## Sunday 8 Nov: P1-4 new features, in this order

Each feature is merged only when finished and tested. Stop where time runs out; whatever isn't done ships in v1.1.

### 1. Home › Tools row + "Pick a document" sheet (S, ~2 h)

**Home, top to bottom:** quick actions (Document · ID Card · Passport · Import) → **Tools** 2 × 2 → folder chips (feature 3) → Recent activity.

**Tools tiles:** min-height 52, icon square 32. Labels up to 2 lines (P1-5).

**Tile actions**
- Passport photo → feature 5. Hide the tile if feature 5 doesn't make v1.0.
- Sign document → picker → Sign a document.
- Shrink PDF → picker → Max file size → share.
- Extract text → picker → Extracted text (English).

**Picker:** `showPickDocumentSheet(context) → ScanDocument?` in `documents/presentation/widgets/`. It lists documents newest first, reusing `DocumentTile` in a compact form.

### 2. Max file size (S–M, ~3 h; plan §20.2, artboard *Max file size*)

- **Share sheet:** new row "Max file size · Under 500 KB" (shown for PDF only) opens the *Max file size* sheet. Options: No limit · Under 1 MB · Under 500 KB · Under 200 KB · Custom (KB), each with its quality tag (Best / Sharp / Good / Readable).
- **Domain:** `ExportOptions.maxBytes` plus a `ShrinkToFit` search in `export/domain/`, running on the background lane.
  1. Render the pages once at 2000 px.
  2. Encode at JPEG 85 → build the PDF in memory → measure.
  3. Too big: lower the quality in steps of 5, down to 55.
  4. Still too big: cut the long edge by 15% per step, down to 1100 px, and repeat.
  5. Last resort: ask "Make it black and white to fit?" and switch to grayscale.
  6. Stop at the first result under the target.
- **Messages:**
  - Show the final size ("438 KB").
  - Under 1400 px or quality under 60: "Small text may be hard to read."
  - Can't fit: "Can't get under 200 KB without making it unreadable. Try fewer pages or black and white."
- **Tests:** unit tests on synthetic pages for each exit (fits at the first try, fits after a quality step, fits after a resize, needs grayscale, can't fit).

### 3. Smart names + folders (M, ~4 h; plan §20.5, artboards *Home*, *Document viewer*)

- **Data:** drift migration **v2 → v3**. Add to `documents`:
  - `folder` (int enum: other, bills, ids, education, receipts)
  - `suggestion` (JSON: title, folder, dismissed)
  - Write the migration test with drift's schema helpers.
- **Rules:** `assets/smart_rules.json` (the plan's keyword table) plus a pure `SmartRules.match(text, mode, date)` that returns a suggested title and folder. Fully unit-tested with the plan's examples: LESCO bill, CNIC number pattern, result card, receipt, no match.
- **When:** after a scan is saved, OCR page 1 in the background (reusing `RecognizePageText`'s dedicated OCR image), match, and store the suggestion. Card modes go straight to the IDs folder.
- **UI**
  - Viewer `SuggestionBanner` ("Looks like an electricity bill · Rename to '…' · Bills", **Apply** / ✕). Dismissing it is stored. Nothing is ever applied silently.
  - Home `FolderChips` with counts, filtering `HomeCubit`.
  - ⋮ › **Move to folder**.
  - Meta line "Bills · 2 pages · 840 KB". The size is the sum of the page files, computed in the repository and cached.

### 4. Signature (M, ~5 h; plan §20.3, artboards *My signature*, *Sign a document*)

**Storage:** `SignatureStore` saves a transparent PNG in app storage. Settings › My signature shows "Saved" with a **Delete** option.

**Create (*My signature*)**
- **Scan from paper:** camera (single) → crop → `pipeline.signatureMask`: gray → background normalise → Otsu → alpha mask → light edge smoothing. Tested on a synthetic scribble.
- **Draw:** a `CustomPainter` with Catmull-Rom smoothed strokes and undo.
- Ink colour: Black · Blue · Original.

**Place (*Sign a document*)**
- The page preview with `OverlayBox` widgets: drag to move, corner handle to resize, ✕ to remove.
- **Add date** places a date stamp ("05 Nov 2026") the same way.
- **Model:** `PageEdits.overlays`, a list of `{kind: signature|date, rect (normalised), ink, text}`. It's freezed/JSON inside the existing `editsJson`, so **no DB migration**. It's drawn into the image only at export (the last step of `renderEdits`) and in previews.

**Also:** new `ActivityType.signed`, appended at the end of the enum because it's stored as an int. Entry points: Viewer › Sign, Tools › Sign document, and ⋮ for ID docs.

### 5. Passport photos (M–L, ~6 h+; plan §20.1, artboards *Passport photo · crop / print sheet*)

**Flow:** capture or import one photo → **crop** → **print sheet**.

**Crop screen**
- A fixed-aspect crop box: 35 × 45 mm (default), 2 × 2 in, or Custom mm.
- Guides: a face oval plus "top of head" and "chin" lines. Pinch and drag to fit.

**Background: Original · White · Light blue**
- Android: ML Kit **Subject Segmentation** (`google_mlkit_subject_segmentation`; the model downloads through Play services).
- iOS: Vision `VNGeneratePersonSegmentationRequest` through a new platform channel.
- If it's unavailable, **hide** White and Light blue rather than fake them.
- This is the riskiest part; see question 3.

**Print sheet**
- Generalise `PrintLayoutCalculator` to `PrintItemSpec(sizeMm, count, paper, gapMm, cutLines)`. ID cards keep their tests green.
- A4: up to 25 photos (5 × 5, 4 mm gaps). 4 × 6 in: up to 6 (2 × 3). Counts 4 · 8 · 12 · 16 · Full.
- Dashed cut lines. 300 DPI from the original. PDF Share / Save, with the "Print at 100% / Actual size" tip.

**Also:** folder IDs, `ActivityType.photoSheet`.

**Cut rule:** if feature 5 isn't finished and tested by Sunday night, it moves to v1.1 and its Tools tile is hidden.

### 6. Urdu text: v1.1

- Not in 9 Nov. "Extract text" opens English Extracted text.
- The *Urdu text · download* artboard is saved in `docs/round4/design/TextUrdu.dc.html`.
- The Settings "Text recognition" section from the new Settings artboard is hidden in v1.0.

**Sunday evening:** owner test build.

---

## Monday 9 Nov: fixes from testing, then release

Build items, mapped to the repo:

| Checklist item | Where / state today | Action |
|---|---|---|
| `targetSdk = 36` | `android/app/build.gradle.kts`: `flutter.targetSdkVersion` | Check what Flutter 3.38.9 resolves (`./gradlew :app:dependencies` / merged manifest); set `targetSdk = 36` explicitly if lower |
| `minSdk` | `minSdk = 24` | Keep; the Mate 10 Lite is Android 8 (API 26) |
| Signed .aab with upload key | `buildTypes.release` still uses the debug key (`docs/release-checklist.md`) | Owner creates the upload keystore; add `key.properties` (git-ignored); **back up the keystore + passwords** |
| Final package name | `com.flashdox.app` is still a placeholder | **Owner confirms before the first upload; it can never change** (question 4) |
| Version | `1.0.0+1` | OK |
| No test ad IDs, logging off | P1-3; `[perf]` / `[ingest]` logs behind `kDebugMode` | Check in the release build |
| Obfuscate + symbols | none | `flutter build appbundle --release -t lib/main_prod.dart --obfuscate --split-debug-info=build/symbols`; keep `build/symbols` |
| Size, OpenCV modules | `pubspec.yaml` opencv hook config | Confirm modules are limited to `imgproc, imgcodecs, photo`; run `--analyze-size` and note the number |
| Only CAMERA permission | merged manifest (P1-3) | As in P1-3 |
| Photo Picker, no broad media access | `image_picker` / `file_picker` | Verify no `READ_MEDIA_IMAGES` in the merged manifest |
| Privacy policy URL | `core/constants/app_info.dart` is still `example.com` | Owner publishes the page (text points in the fix list); paste the URL |
| Store icon 512, feature graphic 1024 × 500, screenshots | `store/` folder | Export the 512 icon from `flash_dox_app_icon_1024.png`; screenshots from the Sunday build |
| Play Console forms | owner | Data safety: none collected · Ads: no · Access: no login · IARC · 13+/18+ · Productivity |

**Account rule:** if the Play account is personal and created after 13 Nov 2023, 9 Nov is the start of a **12-tester, 14-day closed test**, not production (question 5). Upload to **internal testing** first either way.

---

## Effort and cut line

| Block | Estimate |
|---|---|
| P0-1 orientation (incl. fixtures and tests) | 4–5 h |
| P0-2 ID blur | 2–3 h (+ calibration on the owner's phone) |
| P0-3 retake | 1 h |
| P0-4 performance | 5–6 h |
| P0-5 zoom | 2–3 h |
| P1-1 Enhance | 3–4 h |
| P1-2 Camera | 3 h |
| P1-3 ads | 1 h |
| P1-5 text + large-font test | 2–3 h |
| P1-6 viewer | 0.5 h |
| **Saturday total** | **≈ 24–30 h** |
| Sunday features 1–5 | ≈ 20 h |

**Saturday's list doesn't fit in one day.** Recommended order if time runs short:
1. P0-1 and P0-3 (correctness)
2. P1-3 (release blocker)
3. P0-4 point 1 (never show the raw photo)
4. P1-6
5. P1-2, then P1-1 with P0-5
6. The rest of P0-4
7. P1-5

On Sunday, features 1–3 are realistic. Signature is possible. Passport photos is most likely v1.1. This follows the list's own "no half-done features" rule.

**Can't be checked here and needs the owner's phones:**
- Mate 10 Lite timings (P0-4)
- ID sharpness and the blur threshold (P0-2)
- A printed 8-copy sheet (P0-1)
- The largest system font on the owner's phone (P1-5 has an automated test, but one real check helps)
- WhatsApp share-in on both platforms

---

## Questions for the owner (answers change the plan)

1. **Reset default (P1-1):** the list says "Auto, or ID colour for ID/Passport". Should a **document** reset to the Settings › Default filter instead, when the user has changed it?
2. **Zoom (P0-5):** OK to build it on `InteractiveViewer` (no new package), with `photo_view` only if that turns out messy?
3. **Passport photo background (§20.1):** Android ML Kit plus an iOS Vision channel is a lot for Sunday. OK to ship v1.0 **without** White / Light blue (Original only), or to drop Passport photos to v1.1?
4. **Package name:** is `com.flashdox.app` final? It can't change after the first upload.
5. **Play account:** personal or organisation, and created when? This decides closed test vs production on 9 Nov.
6. **Permissions:** OK to remove `INTERNET` for v1.0? Nothing needs it once ads are gone. The Urdu download adds it back in v1.1.
7. **"Share preview" zoom (P0-5):** which screen is meant? The Share sheet has no page preview today.
