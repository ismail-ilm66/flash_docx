# Flash Dox: Round 5 plan

Plan for `flash_dox_fix_list_v5.md` (7 Nov 2026). Release target: **Mon 9 Nov**. This file sits on top of [`docs/round4/PLAN.md`](../round4/PLAN.md); round 4's Play Store checklist still applies.

- **Sources:** the fix list v5, `flash_dox_plan.md` v3.1, and the updated `flashdox_reference.py`.
- **Code state:** `main` at `878cc85`, clean tree.
- **Order:** the list's own: P0-1 → P0-4, then P1-1 → P1-7. One commit per item, so any P1 can be dropped from the build. **P0-1 can't be dropped.**

## Design changes (downloaded 8 Nov)

All 26 artboards were downloaded and compared byte for byte with `docs/round4/design/`. **Only Home changed**, and only in two places:

| Change | File |
|---|---|
| Quick action "Document" → **"Docs"** | [`design/Home.dc.html`](design/Home.dc.html) |
| New **Office** chip between Receipts and Other | same file |

`HomeLight` imports Home, so it picks both up. Every other artboard in `docs/round4/design/` is still current.

The rest of the round's UI work (camera flip and timer, tool pickers, big signature canvas, Sheet 1 | Sheet 2 pill, tight Image output) is described only in the fix list; there are no new artboards for it. It follows the existing components.

---

## P0-1 Portrait photos still come out landscape (release blocker)

### What's actually wrong

Reading the code and the camera plugin turned up **two separate causes**. The fix list names the first. The second also has to be fixed, or landscape shots stay wrong.

1. **Photos with no EXIF tag are never rotated.** `pipeline.dart: bakeOrientation` starts with `if (o == 1 && turns == 0) return false`. A phone that saves sensor-landscape pixels with no tag falls straight through and stays sideways on every screen. This matches what the fix list suspects about the Mate 10 Lite.
2. **The "how the phone was held" value is really the UI orientation on Android.**
   - `camera_page.dart:331` reads `c.value.deviceOrientation`. Round 4 assumed this came from the motion sensor.
   - In `camera_android_camerax` 0.7.2, `DeviceOrientationManager.handleUiOrientationChange` reports `getUiOrientation()`, built from the display rotation and configuration.
   - The camera UI is locked to portrait, so we should expect this to be `portraitUp` however the phone is held, which makes `deviceTurns` always 0.

### Fix: one `CaptureNormalizer`

New `features/scanner/data/capture_normalizer.dart`:

```
normalize(path, CaptureMeta?)   // runs in the worker isolate; shutter stays fast
CaptureMeta { sensorOrientation, lensDirection, deviceTurns }
```

**Step 1: the true device orientation.** A small `DeviceOrientationTracker` around `sensors_plus` (accelerometer, no permission needed).

| Gravity on the phone | Held |
|---|---|
| y ≈ +9.8 | portrait |
| x ≈ +9.8 | landscape left |
| x ≈ −9.8 | landscape right |
| y ≈ −9.8 | portrait upside down |

- **Phone held flat over a page is the usual scanning pose**, and gravity then says nothing. When the x/y part of gravity is below about 3 m/s², keep the last confident value (portrait until there is one).
- Add about 15° of hysteresis so it doesn't flicker near 45°.

**Step 2: the rotation, given the capture stays locked to portrait.**

| EXIF tag | Pixels | Rotation applied |
|---|---|---|
| 2–8 | any | the tag, then `deviceTurns` (as today) |
| missing or 1 | landscape (W > H) | **`sensorOrientation`**, then `deviceTurns` |
| missing or 1 | already portrait | `deviceTurns` only |

The list's formula is `(sensorOrientation − deviceRotation + 360) % 360`. The middle row gives the same result: back camera, sensor 90: portrait → 90°, landscape left → 0°, landscape right → 180°.

The **pixel-shape check is an addition to the list**. Some phones rotate the pixels themselves and write tag 1. Applying the formula unconditionally would turn those photos sideways.

**Front camera** (Passport photo only):
- Add instead of subtract.
- Check the saved file reads un-mirrored using a page of text. Flip once in the normalizer if it doesn't.

**Step 3: one place.**
- `CaptureMeta` replaces `int turns` in `SessionCaptured`, `RetakeShot`, `signatureFromPhoto` and `bakeTurns`.
- Every capture path goes through the normalizer: Document, ID Card, Passport, Passport photo, Signature, Retake.
- Imports pass `null` and get the EXIF bake only.
- The guide-frame rotation reads the same `deviceTurns`.

**Step 4: logging.** `[orient] exif= sensor= device= pixels= final=` per capture, behind `kDebugMode`.

Because only the owner has the failing phone, **dev builds also print those numbers on Adjust edges in small text**, so a tester can read them or photograph the screen without `adb`. That label doesn't exist in release builds.

### Tests
- Extend `test/features/editor/orientation_test.dart` with **tag-less landscape JPEGs** run through every row of the table, back and front camera, with the "up" marker test.
- Unit tests for the tracker: the four poses, flat keeps the last value, hysteresis.

### Acceptance (owner: Mate 10 Lite + one other phone)
The full table in the fix list. Nothing here can stand in for it: neither failing condition exists on a simulator.

---

## P0-2 The grey "marble" patches on white paper

**Today:** `autoFilter` (`pipeline.dart:1006`) passes 8-bit images between each step, exactly the rounding the list describes. There is no `_whiten_paper`.

**Fix**
1. Copy the new reference into `tool/reference/` and re-run `dump_reference.py` to refresh `test/fixtures/reference/`.
2. Rewrite `autoFilter` as a straight port: denoise → **float32** from there (white balance, shadow division with `max(bg, 40)`, float Lab, levels 1 / 99.5, `_whiten_paper`, chroma, unsharp) → rounded to 8-bit **once** at the end.
3. `_whiten_paper`: gate, mid-tone fade and smoothstep exactly as the reference.
   - Write it with OpenCV matrix operations rather than a Dart per-pixel loop. Otherwise a 12 MP page on the Mate 10 Lite would take seconds.
   - Take the percentiles from a copy about 1000 px wide.
4. Color boost and Grayscale are built on Auto, so they pick this up.

**Golden test:** extend the reference comparison to 3 photos, the 2 boxes plus one plain letter page, asserting a **mean difference ≤ 3 levels**. `store/sample_docs/lease1.jpg` can be the letter page unless the owner has a preferred one (question 2).

**Acceptance:** letter page clean white with black text; box photos keep their colours. Check the `[perf]` filter time; if float work breaks round 4's "filter change < 0.8 s" on 1200 px previews, tell the owner.

---

## P0-3 The raw photo still shows while loading

**Today, from reading the code:** Enhance (`shownPreview`) and the viewer (`imageFor`) no longer fall back to the original. They show the exact render, the last render, or the crop-only placeholder, else a spinner. So the list's symptom must come from somewhere else. The remaining uncropped images are:

| Where | Uncropped image | Plan |
|---|---|---|
| Camera page-stack thumbnail | `Capture.thumbPath` returns the base preview (`scan_session_state.dart:41`) | Show a crop-only thumbnail once ready; placeholder until then |
| Adjust edges page strip | `basePreviews` (`adjust_edges_page.dart:168`) | Crop-only thumbnails |
| Adjust edges main image | the whole photo | **Stays:** the user needs the background to place the corners |

**Fix:** the two rows above, plus a widget test that the viewer and Enhance never render a path equal to `originalPath` or a base preview.

**Risk:** if the owner's flash is on another screen, this won't remove it. **Need to know which screen** (question 1).

---

## P0-4 Auto-crop fails on busy backgrounds

**Today:** `_candidateMaps` has no "smooth" maps; scoring has no border-corner penalty.

**Fix:** port from the reference.
- Maps **smooth**, **smooth+lowsat**, **smooth+bright**, with the strong opening (`ko ≈ short side / 10`, odd).
- `score *= 0.45 ** onBorder` **only** for the edges map. The existing `onBorder >= 3` rejection stays, as in the reference.
- Add a check against the Python output for each map, as for the existing ones.

**Tests:** the 2 box photos in `test/fixtures/edges/` still pass. The **cert-on-cloth photo isn't in the round 5 folder** (only the 2 box photos are); it's needed to run that case (question 2).

**Watch:** the big morphological opening is the costly part. Check detection stays near round 4's timing on the Mate 10 Lite.

---

## P1-1 Home: "Docs" button

- `homeDocument` → "Docs". The camera mode stays "Document".
- Alignment: `QuickActionTile` uses `FitText`, which allows 2 lines by default, so at a large font one label can wrap ("ID Card") and throw the row out of line. Pass **`maxLines: 1`** so each label stays on one line and shrinks to fit. The tiles are already equal-width `Expanded`.
- Add these tiles at 360 dp and largest font to `test/ui/large_font_test.dart`.

## P1-2 "Office" folder

- **Enum order matters.** Folders are stored by index (`EnumIndexConverter`), so `office` must be **appended at the end** of `DocFolder`. Using the plan's order (office before other) would silently re-label every saved document. Chip order (… Receipts · **Office** · Other) comes from an explicit list.
- `assets/smart_rules.json`: an Office rule with the list's keywords and names ("Letter – 05 Nov 2026", "Salary slip – Oct 2026", "Notification – 05 Nov 2026").
  - Put it **after** Bills, Education and Receipts, and match on word boundaries. "letter" and "subject:" are broad, and "newsletter" shouldn't match.
- "Move to folder" and the counts use the new value. Unit tests for the new rules.

## P1-3 Passport photo

1. **Camera:** opens the back camera (already the default). Add a **flip** button and a **3 s timer** button, shown only for this entry. Front-camera files saved un-mirrored (P0-1).
2. **Background: Original · White · Light blue**, as small live previews.
   - Android: `google_mlkit_subject_segmentation`. Pin a version compatible with the installed `google_mlkit_commons`. The model comes via Play services; confirm it works with `INTERNET` removed from the release manifest.
   - iOS: a new Swift platform channel for Vision person segmentation (iOS 15+, within our target).
   - Feather the mask 2–3 px. If segmentation isn't available, hide White and Light blue.
   - Run `--analyze-size` and report the cost; the plan says to tell the owner above about 3 MB.
3. **Hint:** see P1-7.
4. **Retake leaves the screen grey.** `_retake` in `photo_crop_page.dart` reads correctly on paper, so this one needs reproducing first (the simulator's "no camera" path won't show it; use a device). Add an `errorBuilder` to the `Image.file`, and a `ValueKey(_photo)`.
5. **"Next" / "Make print sheet" look disabled: cause found.** `_placement` is assigned inside the `LayoutBuilder`, which runs **after** the top bar and bottom button have been built with `_placement == null`. They stay grey until the next rebuild. Fix: `addPostFrameCallback` → `setState` after the first placement.

## P1-4 Tool pickers (Sign · Shrink PDF · Extract text)

- `pick_document_sheet.dart`: per-tool title, two big buttons (**Scan new**, **From photos**), then "Or pick a document" and the list.
- New `ToolTarget { sign, shrink, extractText }` on `CameraArgs` → `EditorArgs`. Enhance's `_onSaved` goes **straight to that tool** with the new document instead of the viewer.
- From photos: import → Adjust → Enhance with the same target.
- Shrink PDF stays Flash Dox documents only.
- Test: a bloc or widget test that saving with a `ToolTarget` routes to the tool.

## P1-5 Signature

1. Orientation: P0-1.
2. Canvas: full width, about half the screen height (today a fixed 230 px, `my_signature_page.dart:112`), with a baseline and a "Sign here" hint.
3. **Expand:** a full-screen canvas drawn sideways with `RotatedBox`, with strokes mapped back so the saved signature is upright.
4. **Crop to ink + small margin.** Drawn signatures already do this (`DrawPad.toImage`). The **scan path doesn't**, so add it to `pipeline`'s signature step.
5. Hint: see P1-7.
6. `signChange` → "Change".

## P1-6 Print layout

1. One large preview for all three outputs, full width, A4 aspect for the PDFs, using the same zoom widget as the viewer (`ZoomablePages`), which also covers item 4.
2. **Sheets:** chosen option is a compact **"Sheet 1 | Sheet 2" segmented pill** above the preview (`SegmentedPills` exists), used for every multi-sheet preview. It replaces `_SheetChip`.
3. **Tight Image output:** front above back, 4 mm gap, 4 mm white border, no A4 page.
   - Card: 93.6 × 120 mm, about 1106 × 1417 px at 300 DPI.
   - Passport: data page alone with the border, 133 × 96 mm.
   - Changes in `sheet_image_renderer.dart` and the `PrintOutput.image` case. Update the calculator tests; the preview follows the same layout.

## P1-7 Camera hints per context

`CameraArgs.hint` (an enum: document, idCard, passport, passportPhoto, signature, extractText). `_guideText` uses it, and each entry point passes its own. All six strings are from the list. Document and ID Card already exist (`cameraHintDocument`, `cameraHintCard`); the other four are new. Retakes keep their side label.

## P2

- Extend `test/ui/large_font_test.dart` to every button label at 360 dp and largest font.
- Confirm the P0-1 logging and the dev-only label are off in release.

---

## Effort and cut line

| Item | Estimate |
|---|---|
| P0-1 | 4–5 h |
| P0-2 | 3–4 h |
| P0-3 | 1 h |
| P0-4 | 2 h |
| P1-1, P1-2 | 1.5 h |
| P1-3 (without background) | 2–3 h |
| P1-3.2 background (Android + iOS) | 4–5 h |
| P1-4 | 3 h |
| P1-5 | 2–3 h |
| P1-6 | 3 h |
| P1-7 | 0.5 h |
| **Total** | **≈ 26–31 h** |

**That doesn't fit in what's left of Sunday.** Recommended order if time runs short: P0-1 → P0-2 → P0-4 → P0-3 → P1-1, P1-2, P1-7 → P1-3 bugs (items 4 and 5) → P1-6 → P1-4 → P1-5. **Move to v1.1 first:** P1-3.2 (background), then P1-5.3 (sideways expand canvas), then the P1-3.1 flip and timer.

**Can only be confirmed on the owner's phones:** every P0-1 acceptance row, the Passport-photo retake bug, segmentation availability, and the timing checks on the Mate 10 Lite.

---

## Questions for the owner

1. **P0-3:** on which screen does the raw photo flash? A short screen recording would settle it. In the code, Enhance and the viewer no longer use it, and Adjust edges has to show the whole photo.
2. **Test photos:** please send the **cert-on-cloth** photo (P0-4; it isn't in the round 5 folder). And is `store/sample_docs/lease1.jpg` fine as the plain letter page (P0-2), or is there a specific one?
3. **P1-3.2:** if it comes down to time, is it OK to ship without White / Light blue backgrounds, as in the current build?
