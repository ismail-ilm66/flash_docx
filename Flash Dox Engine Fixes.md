Flash Dox · build review round

# Engine fixes: scanning, image quality, export and flows

Every non-UI item from the 5 Nov fix list. For each one: what testers saw, why it happens in today's code, what we want instead, and how we'll know it's done.

**Source:** `flash_dox_fix_list.md` (P0 and P1 items) **Checked against:** the code on branch `design-canvas-restyle`, 4 Nov 2026 **Not covered:** design-match (P2) and copy-only items

## At a glance

P0 items block release and come first. The status describes the code as it is today.

Cause found Not started Partly there In progress Works today

| ID | Fix | Status | One-line cause |
| --- | --- | --- | --- |
| X-1 | [App crashes when importing large photos](#x1) | Cause found | An OpenCV image is freed twice for photos over 4000 px |
| P0-1 | [Auto edge detection never finds the document](#p01) | Cause found | One fragile edge-only strategy; failures fall back to a 2% inset that looks like the full frame |
| P0-2 | ["Auto" filter makes images grainy and grey](#p02) | Cause found | Shadow removal divides by unclamped dark backgrounds |
| P0-3 | [Camera preview stretched](#p03) | Partly there | 16:9 capture preset; preview now cover-fit but not yet 4:3 |
| P0-4 | [Camera doesn't focus](#p04) | Not started | Focus and exposure are never set; no tap-to-focus |
| P0-5 | [No feedback when a photo is taken](#p05) | Partly there | Only a light haptic; no sound, flash or animation |
| P0-6 | [Standard export looks poor](#p06) | Cause found | Warped straight down to 2000 px with cubic sampling |
| P0-7 | [Back button loses scans / exits silently](#p07) | Not started | No back-button handling anywhere |
| P0-8 | [OCR accuracy is low](#p08) | Cause found | OCR reads the filtered 1600 px preview, not a clean full-size image |
| P0-9 | [Imports skip the auto clean-up](#p09) | Partly there | One shared pipeline exists, but it only crops and the default filter is never applied |
| X-2 | [Sharing into the app doesn't work on iOS](#x2) | Not started | Share-in exists on Android only |
| P1-1 | [ID print layout: cut-ready](#p11) | Partly there | Real-size maths is right; cut guides, swap, single-image output missing |
| P1-2 | [Share ID card as one image](#p12) | Not started | Export has no layout option |
| P1-3 | [Add pages on Adjust edges](#p13) | In progress | Built, not yet committed or tested on a device |
| P1-4 | [Viewer: drag to reorder, add pages](#p14) | Partly there | Reorder is a separate sheet; "+" opens the camera only |
| P1-6 | [Single mode moves on after one photo](#p16) | Works today | Needs a check on a phone only |
| P1-7 | [Default document name](#p17) | Not started | Names are "Scan 2026-11-05 1342"; no duplicate numbering |
| P1-8 | [Settings defaults are ignored](#p18) | Cause found | The default filter is saved but never read when a scan is created |
| P1-9 | [Crop corners can bend or cross](#p19) | Not started | Corner drags aren't checked for a valid shape |

Release blockers

## P0 · Broken core features

X-1 · P0

### App crashes when importing large photos

Cause found

Seen

Not on the fix list. Found while testing on the iOS Simulator: importing the built-in sample photos crashes the app as soon as the picker closes. There's no error message; the app just disappears.

Why

Every image goes through `_normalize` in `opencv_image_processor.dart`, which caps the long edge at 4000 px. When a photo is bigger, `fitLongEdge` frees the original image and returns a smaller copy. Then the `finally` block frees the original again. Freeing the same native memory twice crashes the app (the crash report points at `cv_Mat_close`).

It only happens for photos wider than 4000 px. iPhones shoot 4032 × 3024, and many Android phones shoot exactly 4000 × 3000 and just escape it. That's likely why it didn't show up in the Android review.

Want

Free each image exactly once. Make `fitLongEdge`'s ownership rule explicit, and check the other callers that use the same pattern.

Done when

- Importing a 4032 × 3024 photo and a 48 MP photo works on iOS and Android.
- A unit test runs `_normalize` on an image larger than 4000 px.

P0-1

### Auto edge detection never finds the document

Cause found

Seen

Every capture opens Adjust edges with the corners at the photo's edges. That happens in single, batch and ID card modes, even for a light card on a dark table.

Why

Detection is running, but it fails every time. When it finds nothing, the app falls back to a 2% inset rectangle, which looks exactly like "full frame". The detector (`detectDocumentQuad` in `pipeline.dart`) has a few weaknesses:

- **Edges only.** It uses Canny with two fixed threshold pairs (50/150, 20/80). It has no region-based pass, which is what finds a pale card on a dark table, and the fixed thresholds fail in low light.
- **Outer contours only** (`RETR_EXTERNAL`), after dilating twice. As soon as the page edge touches table texture or the photo border, the page merges into a bigger blob that isn't a four-sided shape, and it gets thrown away.
- **Strictly four points.** A shape that simplifies to five or six points (a rounded card corner, a curled page) is rejected. Nothing tries a bounding rectangle or convex hull instead.
- **Never tested on real photos.** The unit test uses a drawn, perfect rectangle, so these failures never showed up.

Two checks from the list are fine: images are made upright (EXIF) before detection, and the crop screen shows that same upright image, so the corners land in the right place. There is no logging yet.

Want

1. Work on a copy about 1000 px on the long edge, in a background isolate.
2. **Edges pass:** gray → blur → Canny with thresholds set from the image's median brightness (0.66× and 1.33×) → close (5 × 5) → dilate once.
3. **Regions pass:** Otsu threshold on gray *and* on the colour-saturation channel → close.
4. Collect contours from both passes (`RETR_LIST`), simplify them, and keep convex four-sided shapes covering more than 15% of the image. For big shapes that aren't four-sided, try the bounding rectangle or hull.
5. Score each candidate by area × how rectangular it is. In ID mode, favour the 85.6 : 54 shape; in passport mode, 125 : 88.
6. Pick the best, order the corners TL, TR, BR, BL, and scale back up to full size.
7. **If nothing is found:** ID/Passport use the on-screen guide frame; other modes use a 5% inset (never the exact full frame). Show "Couldn't find the edges — drag the corners".
8. Log every result: found or not, score, time taken.
9. Optional on iOS: Apple's built-in rectangle detection.

Done when

- 30 real photos live in `test/fixtures/edges/` with their true corners marked: pages, receipts, ID cards and books, on dark, light, wooden and patterned surfaces, tilted up to 30°, some in low light.
- On at least 26 of the 30, every corner is within 3% of the image width.
- Under 300 ms on a mid-range Android phone.
- Unit tests run the whole set.

P0-2

### "Auto" filter makes images grainy and grey

Cause found

Seen

Auto turns photos into a grainy, near black-and-white sketch, with coloured speckle in dark areas and lost colour (for example, a card's green background). Users need colour documents, not only print-ready black and white.

Why

Auto runs three steps: shadow removal, CLAHE contrast, then a white balance.

- Shadow removal divides each colour channel by a blurred estimate of the background, with no lower limit. In dark areas the divisor is tiny, so noise is multiplied many times over. That's the speckle.
- Because edge detection fails (P0-1), the dark table stays in the frame, so a large part of every image goes through this dark-area problem.
- There is no denoise step and no saturation step. Color boost and Grayscale are built on top of Auto, so they inherit the same problems.
- B&W print is mostly right: adaptive threshold, then a median filter. Its block size uses the long edge (the list says width) and it doesn't normalise first.

Want

Always crop first, then filter.

- **Auto (colour, default):** light denoise → white balance → shadow correction with the divisor kept at 40 or above and blended at no more than 70% → mild CLAHE on brightness only (1.5–2.0) → +10% saturation. No thresholding, no strong sharpening. Stamps, logos and photos stay in colour.
- **Color boost:** Auto + 25% saturation and a little contrast.
- **Grayscale:** Auto → gray → normalise.
- **B&W print:** gray → normalise → adaptive threshold (block about 1/40 of the width, odd; C 10–15) → median 3. The only pure black-and-white filter.
- **Original:** crop and rotate only.

Original, Auto and Color boost stay full colour everywhere: the preview, saved JPG/PNG files, and PDFs. New installs default to Auto.

Done when

- On the P0-1 photo set, Auto has no visible grain or speckle at 100% zoom, keeps colour, and the page background is white or near-white.
- Side-by-side before/after images for 5 samples are attached to the PR.

P0-3

### Camera preview stretched

Partly there

Seen

In all modes the preview looks stretched tall, and in ID mode the card can't fit the guide frame.

Why

The old build stretched the camera feed to the screen. On this branch the preview now keeps the camera's real proportions and crops to fill its area, so the stretching itself should be gone. That still needs checking on a phone.

Two gaps remain. The capture preset is `ResolutionPreset.veryHigh`, which is 16:9 on most Android phones, so what you see isn't exactly what's captured. And the guide frame isn't mapped into the photo's coordinates.

Want

- A 4:3 capture preset (check `ResolutionPreset.max` on the test phones) shown in a 3:4 preview box, so what you see is what you capture.
- The ID/Passport guide frame mapped into photo coordinates with the same transform. That mapping also feeds the P0-1 fallback.

Done when

A printed A4 page and an ID card look correctly proportioned on screen (measure with a ruler), and the ID card fits the ID guide frame.

P0-4

### Camera doesn't focus

Not started

Why

The camera is never told to autofocus or auto-expose, and nothing handles a tap on the preview.

Want

- Turn on auto focus and auto exposure when the camera starts.
- **Tap to focus:** focus and exposure jump to the tapped point, with an animated focus ring there.
- Before each capture, lock focus briefly (or wait for it to settle) so pages come out sharp.

Done when

Text on an A4 page held 30 cm away is sharp in the photo, and tap-to-focus works.

P0-5

### No feedback when a photo is taken

Partly there

Why

Pressing the shutter gives a light haptic and nothing else. The shutter is already disabled while a photo is being saved, so a double tap won't take two.

Want

- A short shutter **sound**, with a "Shutter sound" setting (on by default). This needs an audio package and a sound file.
- A medium **haptic** instead of the light one.
- A quick **white flash** over the preview (about 150 ms).
- The thumbnail **flies into the page stack** and the counter bumps.
- The shutter **shrinks while pressed**.

Done when

All five happen on every capture, and turning the setting off silences the sound.

P0-6

### Standard export looks poor

Cause found

Seen

Standard quality is visibly worse than High. High looks fine.

Why

Both qualities already render from the original photo, not the preview cache. The problem is how Standard shrinks the image: the perspective correction warps straight down to 2000 px using cubic sampling. Shrinking a 4000 px photo by half that way skips pixels instead of averaging them, so fine text gets jagged and grainy. The size is also below the 2480 px the list asks for.

Want

- **Standard:** warp at full size, then shrink to 2480 px on the long edge (A4 at 300 DPI) with area averaging (`INTER_AREA`); JPEG 85.
- **High:** original resolution, JPEG 95 (as today).
- Never enlarge an image. Put JPEGs in the PDF as they are, without re-encoding.

Done when

At 100% zoom, Standard and High text look equally clean on the same page, and Standard is 2480 px on the long edge (or smaller if the original is).

P0-7

### Back button loses scans and exits silently

Not started

Why

No screen intercepts back. Pressing back on Home closes the app, and pressing back during a scan throws the pages away without asking.

Want

- **Home:** "Leave Flash Dox?" with **Leave** and **Stay**.
- **Camera with captured pages, Adjust edges and Enhance** (an unsaved scan): "Discard this scan? N pages will be lost." with **Discard** and **Keep scanning**. The same dialog for the ✕ button and the iOS swipe-back.
- Every other screen: normal back.

Done when

Android back, ✕ and iOS swipe-back all show the right dialog on these screens, and no unsaved scan is ever lost without one.

P0-8

### OCR accuracy is low

Cause found

Seen

Many wrong letters ("POR REGISTRATION VITH FEDRAL GOVERNNENT…").

Why

Text recognition reads the page's preview image. That's a JPEG shrunk to 1600 px with the user's filter already applied, so it carries the Auto grain from P0-2 or the hard B&W threshold. Small text loses detail at that size.

Want

- A dedicated OCR image for each page: cropped and perspective-corrected → gray → mild contrast → light denoise, at full resolution, and never the user's chosen filter.
- Cache it per page, and clear the cache when the crop changes.
- The text box stays editable so users can fix mistakes before copying (it already is).

Done when

The sample page from the review reads correctly, and the same page reads the same way whichever filter the user picked.

P0-9

### Imported images skip the auto clean-up

Partly there

Seen

Photos from the gallery or files, and images shared in from WhatsApp, don't get the automatic clean-up.

Why

There's already one shared step (`PreparePages`), used by the camera, Home import and share-in. But it only sets the crop. It never applies the default filter (see P1-8). And since edge detection fails (P0-1), every source ends up looking untouched. The X-1 crash also happens inside this shared step.

Want

Every image goes through the same steps, whether it comes from the camera, Photos, Files or share-in: upright (EXIF) → edge detection → default filter → Adjust edges → Enhance. Keep it one shared use case (for example `PrepareScanPage`) so the entry points can't drift apart.

Done when

The same photo gives the same result whether it's captured, imported from Photos, imported from Files, or shared in from WhatsApp, with a test that runs the use case for each source.

X-2

### Sharing into the app doesn't work on iOS

Not started

Why

Receiving shared images is built only on Android (in `MainActivity.kt`). On iOS the app logs a "no implementation" error at start-up, which is harmless, but Flash Dox doesn't appear in the share sheet. The list's definition of done includes "share-in from WhatsApp".

Want

An iOS Share Extension that accepts images and PDFs and hands them to the same pipeline (P0-9). It has to be set up in Xcode with an App Group.

Done when

Sharing a photo from WhatsApp or Photos on an iPhone opens it in Flash Dox and runs the P0-9 pipeline.

After the P0s

## P1 · Missing or wrong behaviour

P1-1

### ID card print layout: make it cut-ready

Partly there

Goal

In the owner's words: to get 8 copies, put 8 fronts on the front sheet and 8 backs on the back sheet, print double-sided, then cut the sheet into 8 real-size ID cards.

Today

Already right: cards at real size (85.6 × 54 mm), 6 mm gaps, the group centred on A4, backs mirrored for long-edge flip (`x = 210 − x − w`), copies 1/2/4/6/8, and passports at 125 × 88 mm with 4 copies rotated.

Missing: cut guides, a way to swap front and back, and the right Image output. Today Image lays out a grid of copies; it should be one front-above-back image.

Want

- Thin light-grey **corner crop marks** in the gaps on both sheets, with a "Cut guides" toggle (on by default).
- A **Swap front/back** button, for when the back was scanned first.
- **Image output:** one 300 DPI image, front above back on white, with the copies selector hidden.
- **One-page PDF** (single-sided printers): front and back side by side, N pairs: 1, 2, 4.
- The sheet toggle also responds to a swipe.

Done when

The 8-copy double-sided PDF is printed at 100% on a real printer and cut along the guides, giving 8 cards with front and back aligned within about 1.5 mm. A photo is attached.

P1-2

### Share an ID card as one image

Not started

Want

For ID card and passport documents, the Share sheet gets **Layout: One image (front + back)** (default) or **Separate images**. One image gives the same output as P1-1's Image. For PDF, it means both sides on one page.

Today

The export options have no layout setting; every page is exported separately.

Done when

Sharing a 2-sided ID as JPG sends one image by default, and switching to Separate sends two.

P1-3

### Add pages on the Adjust edges screen

In progress

Want

A "+" tile at the end of the page strip opens Camera / Photos / Files. The new pages join the current scan.

Today

Built on this branch but not yet committed. New pages go through the same pipeline as every other source and are appended to the scan. The tile shows for new scans in single and batch modes. For a document that's already saved, pages are added from the viewer instead (P1-4).

Done when

Adding pages from each of the three sources works on a phone and the pages land at the end of the scan.

P1-4

### Viewer: drag to reorder, add pages on screen

Partly there

Today

Long-pressing a page opens a separate reorder sheet. The "+" tile goes straight to the camera. The ⋮ menu still has Add pages and Reorder.

Want

- Long-press and drag thumbnails to reorder them right in the strip, keeping the existing reorder logic underneath.
- "+" opens Camera / Photos / Files, reusing the P1-3 flow.
- The ⋮ menu keeps only Rename, Delete page and Delete document.

Done when

The new order is saved after a drag, and pages added from each source appear in the document.

P1-6

### Single mode moves on after one photo

Works today

Today

In single mode, the scan finishes itself after one capture and opens Adjust edges, with no counter or Done step. A unit test covers this. It only needs a check on a phone.

P1-7

### Default document name

Not started

Today

New documents are named like "Scan 2026-11-05 1342", "ID card 2026-11-05 1342" or "Passport …", and nothing prevents two documents with the same name. The Share sheet's file name already defaults to the document's name.

Want

`Flash Scan - 05 Nov 2026`. If that name is taken, add ` (2)`, ` (3)` and so on.

Done when

Three scans on the same day are named "Flash Scan - 05 Nov 2026", "… (2)" and "… (3)", and the Share sheet suggests the same name.

P1-8

### Settings defaults are ignored

Cause found

Why

The default filter is saved in Settings but never read: new pages are created with a crop only, so they always get the built-in default (Auto). The Share sheet already picks up the default format and page size. There's no default quality setting at all.

Want

- The default filter (for example B&W print) is applied to new pages and shows as selected in Enhance.
- The default format, page size and quality are pre-selected in the Share sheet. This needs an Image quality setting.

Done when

After changing each default in Settings, the next scan and the next share both start with it.

P1-9

### Crop corners must keep a valid shape

Not started

Why

A dragged corner is accepted wherever it goes, so the crop can end up bent inwards or with crossing edges. A convexity check already exists in the code, but drags don't use it.

Want

Reject a corner move that would make the shape bent or self-crossing; the corner stays at its last valid spot.

Done when

No drag can produce a bent or crossed crop, with a unit test for the rejected cases.

## Needed from the owner

- **30 test photos for P0-1**, ideally with the four true corners marked (or I can mark them). The detector and test harness can be built without them, but the 26-of-30 target can't be measured until they're in.
- **Real hardware checks** that a simulator can't cover: the 300 ms target on a mid-range Android, focus at 30 cm, the printed and cut 8-card sheet, and the two-phone + iPhone test pass.
- **A shutter sound file** (or approval to use a free one) for P0-5.

Left out of this document

- All P2 design-match items, P1-5 (batch count in the camera top bar), P1-10 (Share sheet details) and P1-11 (magnifier). Most of these are already done or in progress on the `design-canvas-restyle` branch.
- App icon, native splash and the supplied logo files.