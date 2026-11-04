# Flash Dox — Flutter Build Plan (v2)

> Offline document scanner: capture or import → auto clean-up → manual adjust → view → share as images or PDF.
> Flutter · Clean Architecture · flutter_bloc · feature-first · DRY.
> Designs: "Flash Dox App Design" canvas (dark + light).

---

## 1. Scope

### In v1
| Area | What it does |
|---|---|
| **Capture** | Camera with 4 modes: Single, Batch, ID Card (front + back), Passport. Flash toggle. |
| **Import** | Gallery (multi-select), Files app, and images shared *into* Flash Dox from other apps (WhatsApp, Files, etc.). |
| **Auto clean-up** | Edge detection, perspective correction, auto-rotate, auto enhance (contrast, brightness, colour, shadow removal). |
| **Manual adjust** | Drag corners (with magnifier), rotate left/right, re-run auto edges, retake, delete page. Filters: Original, Auto, Color boost, Grayscale, B&W print. Brightness + contrast sliders. Apply to all pages. |
| **Documents** | Each scan session = one multi-page document. Rename, reorder, add pages, delete. |
| **Home** | Quick actions + recent activity list (latest action per document). |
| **Text (OCR)** | Extract text from a page (or all pages), edit, cut, copy, select all, share as `.txt`. Offline. |
| **Share** | PDF, JPG or PNG via the phone's share sheet, or save to phone. PDF is built at share time; the app never opens PDFs. |
| **Print layouts** | ID card and passport sheets at real size: image, double-sided PDF, one-page PDF, 1–8 copies. |
| **Rewarded video** | Unlocks premium export options per export (§9). |
| **Settings** | Theme (System / Light / Dark), scan and share defaults, storage, Privacy Policy, FAQ, rate/share app. |

### Removed (from the old Figma)
Manager, Converter/Tools, File Reader (Word/Excel/PPT/PDF), To Word mode, sign-up, folder grid, Favorites, Trash, per-app share buttons.

### Later (v1.1+)
Live edge outline in the camera + auto-capture · more OCR scripts · PDF password · cloud backup (only if users ask).

---

## 2. Screens and navigation

| # | Screen | Canvas artboard | Theme |
|---|---|---|---|
| 1 | Splash | Splash | Dark |
| 2 | Home | Home / Home · light | Both |
| 3 | Camera | Camera | Always dark |
| 4 | Adjust edges | Adjust edges | Always dark |
| 5 | Enhance | Enhance | Always dark |
| 6 | Document viewer | Document viewer / · light | Both |
| 7 | Extracted text | Extracted text / · light | Both |
| 8 | Share sheet (bottom sheet) | Share sheet / · light | Both |
| 9 | Print layout (ID / Passport) | ID card print layout / · light | Both |
| 10 | Unlock dialog | Unlock with video / · light | Both |
| 11 | Settings | Settings / · light | Both |

```
Splash → Home ─┬─ [camera button / quick action] → Camera → Adjust edges → Enhance → Viewer
               ├─ [Import] → (picker) → Adjust edges → Enhance → Viewer
               ├─ [document row] → Viewer ─┬─ Edit   → Adjust edges / Enhance
               │                           ├─ Text   → Extracted text
               │                           ├─ Print  → Print layout   (ID / Passport docs)
               │                           └─ Share  → Share sheet → (Unlock dialog) → OS share / save
               └─ Settings (tab)
```

**Bottom nav:** Home · centre camera button · Settings. The active tab follows the current route (`StatefulShellRoute` index), which fixes the old "Home always highlighted" bug.

**Splash:** `flutter_native_splash` shows the static icon instantly; the Flutter splash then plays the 3 logo frames (≈ 900 ms total) while DI, DB and prefs load, then routes to Home.

---

## 3. State management: flutter_bloc

- **Bloc** where flows are event-driven: `ScanSessionBloc`, `PageEditorBloc`, `ExportBloc`.
- **Cubit** for simple screens: `HomeCubit`, `ViewerCubit`, `OcrCubit`, `PrintLayoutCubit`, `SettingsCubit`, `ThemeCubit`, `RewardCubit`.
- `sealed` states (`Idle / Working(progress) / Done / Failed`) for every long job.
- `bloc_test` for every Bloc/Cubit.

| Concern | Package |
|---|---|
| DI | `get_it` + `injectable` |
| Routing | `go_router` |
| Models / unions | `freezed`, `json_serializable` |
| Errors | `fpdart` (`Either<Failure, T>`) |
| DB | `drift` |
| Prefs | `shared_preferences` |

---

## 4. Architecture

```
presentation (pages, widgets, blocs) → domain (entities, repo contracts, use cases) ← data (models, sources, repo impls)
```

- Domain is pure Dart. Image processing, OCR, PDF and ads are **interfaces in domain**, implemented in data — so they're swappable and mockable.
- Heavy work (image processing, PDF, OCR batches) runs off the UI thread in isolates.

### Folder structure

```
lib/
├── main.dart / main_dev.dart / main_prod.dart
├── app/
│   ├── app.dart              # MaterialApp.router, global BlocProviders
│   ├── router/               # routes, shell route, transitions
│   ├── di/                   # injectable config
│   └── theme/                # tokens, light/dark ThemeData, ThemeExtensions
├── core/
│   ├── error/  usecase/  extensions/  utils/
│   ├── constants/            # paper sizes, card sizes, limits
│   └── services/             # FileStore, ShareService, SaveService, PermissionService, IsolateRunner
├── shared/widgets/           # §12
└── features/
    ├── splash/
    ├── documents/            # Home list, Viewer, rename/reorder/delete, activity
    ├── scanner/              # camera, modes, import, share-intent
    ├── editor/               # edges, filters, sliders, page rendering
    ├── ocr/
    ├── export/               # PDF + image export, share/save
    ├── print_layout/         # ID / passport sheets
    ├── rewards/              # rewarded ads + feature gate
    └── settings/
```

Each feature: `data/ · domain/ · presentation/`.

---

## 5. Domain model

Editing is **non-destructive**: the original photo is never changed. Each page stores its edit settings; the processed image is a cache that can always be rebuilt.

```dart
enum ScanMode { single, batch, idCard, passport }
enum FilterType { original, auto, colorBoost, grayscale, bwPrint }
enum CardSide { front, back }
enum ActivityType { created, edited, sharedPdf, sharedImages, savedToPhone, textCopied, printLayout }

@freezed
class Quad with _$Quad {            // normalised 0..1 corners, TL, TR, BR, BL
  const factory Quad(List<Offset2> points) = _Quad;
}

@freezed
class PageEdits with _$PageEdits {
  const factory PageEdits({
    Quad? crop,                      // null = full image
    @Default(0) int quarterTurns,
    @Default(FilterType.auto) FilterType filter,
    @Default(0) double brightness,   // -100..100
    @Default(0) double contrast,     // -100..100
  }) = _PageEdits;
}

@freezed
class ScanPage with _$ScanPage {
  const factory ScanPage({
    required String id,
    required String originalPath,
    required PageEdits edits,
    required int order,
    CardSide? side,                  // ID card only
    String? processedPath,           // cache, rebuilt when edits change
    String? thumbPath,
    String? ocrText,                 // cache, cleared when edits change
  }) = _ScanPage;
}

@freezed
class ScanDocument with _$ScanDocument {
  const factory ScanDocument({
    required String id,
    required String title,
    required ScanMode mode,
    required List<ScanPage> pages,
    required DateTime createdAt,
    required DateTime updatedAt,
    Activity? lastActivity,          // shown on Home
  }) = _ScanDocument;
}
```

### Repositories (contracts)

```dart
abstract interface class DocumentRepository {
  Stream<List<ScanDocument>> watchAll({String? search});
  Future<Either<Failure, ScanDocument>> create(ScanMode mode, List<ScanPage> pages);
  Future<Either<Failure, Unit>> rename(String id, String title);
  Future<Either<Failure, Unit>> addPages(String id, List<ScanPage> pages);
  Future<Either<Failure, Unit>> reorder(String id, List<String> pageIds);
  Future<Either<Failure, Unit>> updatePage(ScanPage page);
  Future<Either<Failure, Unit>> deletePage(String pageId);
  Future<Either<Failure, Unit>> delete(String id);
  Future<Either<Failure, Unit>> logActivity(String id, ActivityType type);
  Future<Either<Failure, int>> storageUsedBytes();
}

abstract interface class ImageProcessor {          // OpenCV impl in data/
  Future<Quad?> detectEdges(String imagePath);
  Future<String> render(String originalPath, PageEdits edits, {required RenderSize size});
  Future<PageEdits> autoEdits(String imagePath);   // auto crop + rotate + filter
}

abstract interface class TextRecognizer {
  Future<Either<Failure, String>> read(String imagePath);
}

abstract interface class PdfBuilder {
  Future<File> fromPages(List<String> imagePaths, PdfOptions o);
  Future<File> printSheet(PrintLayoutSpec spec);
}

abstract interface class RewardGate {
  Future<RewardResult> unlock(PremiumFeature f);   // granted / cancelled / offline
}
```

`RenderSize` = `thumb` (≈ 300 px), `preview` (≈ 1600 px long edge, used while editing) or `full` (original resolution, export only).

---

## 6. Image pipeline (OpenCV via `opencv_dart`)

Runs in an isolate. Each step is a small pure function, so it's testable with sample photos.

**On capture/import (`autoEdits`):**
1. Read EXIF orientation → upright image.
2. Downscale to ~1000 px for detection.
3. Grayscale → Gaussian blur → Canny → dilate → `findContours`.
4. Largest 4-point contour (`approxPolyDP`) covering > 20% of the image = document. Otherwise fall back to the full frame with a small inset.
5. ID card / passport modes: snap the quad to the card's aspect ratio (85.6 : 54 / 125 : 88).
6. Default filter = `auto`.

**Render (`render`):**
1. Perspective warp to the quad (`getPerspectiveTransform` + `warpPerspective`) at the requested size.
2. Rotate by `quarterTurns`.
3. Filter:
   - **Auto:** remove shadows (divide by a heavily blurred background), then CLAHE on the L channel, then a gentle white-balance.
   - **Color boost:** Auto + saturation lift.
   - **Grayscale:** Auto, then to gray.
   - **B&W print:** gray → adaptive threshold (Gaussian) → light denoise. Best for photocopies.
4. Brightness / contrast: `convertScaleAbs(alpha, beta)` mapped from the sliders.
5. Encode JPEG (quality 90) to the cache folder.

**Performance rules**
- Sliders render the `preview` size only, debounced (~80 ms).
- Full resolution is rendered only at export time.
- One shared isolate worker for the pipeline, so two renders don't run at once.
- "Hold to compare" shows the original preview, with no re-render.

---

## 7. Scan modes (strategy pattern)

```dart
abstract interface class ScanModeRules {
  int? get maxPages;                 // single = 1, idCard = 2, passport = 1, batch = null
  List<CardSide>? get sides;         // idCard = [front, back]
  double? get aspectRatio;           // card / passport snap
  String guideLabel(int captured);   // "Front side", "Back side", …
  bool isComplete(int captured);
}
```

The camera UI reads these rules; there's no `if (mode == …)` in widgets.

| Mode | Flow |
|---|---|
| Single | 1 capture → Adjust edges → Enhance → Viewer |
| Batch | Many captures (counter on the page stack) → review all → Viewer |
| ID Card | Guided "Front side" → "Back side" → Adjust → Enhance → Viewer (Print enabled) |
| Passport | Guided data-page capture → Adjust → Enhance → Viewer (Print enabled) |

---

## 8. Print layouts (ID card & passport)

All sizes are in millimetres. The PDF is built with the `pdf` package in real units, so it prints at true size.

| Item | Size |
|---|---|
| A4 | 210 × 297 mm |
| ID card (ID-1: CNIC, licence) | 85.6 × 54 mm |
| Passport data page (ID-3) | 125 × 88 mm |
| Gap between items | 6 mm |

### Copies per sheet

| Copies | ID card grid (cols × rows) | Passport grid |
|---|---|---|
| 1 | 1 × 1 | 1 × 1 |
| 2 | 1 × 2 | 1 × 2 |
| 4 | 2 × 2 | 2 × 2, rotated 90° (88 × 125) |
| 6 | 2 × 3 | — (doesn't fit at real size) |
| 8 | 2 × 4 | — |

The whole group is centred on the sheet: `originX = (210 − groupW) / 2`, `originY = (297 − groupH) / 2`.

### Outputs
1. **Image:** front above back on a white background, rendered at 300 DPI, saved as JPG/PNG.
2. **PDF double-sided:** page 1 = N fronts, page 2 = N backs. Backs are mirrored left-to-right so each lands behind its front after a long-edge flip: `xBack = 210 − xFront − cardW`. Rows stay the same.
3. **PDF one page:** front and back side by side on one A4, repeated for N pairs. This is for single-sided printers (classic CNIC copy). Passport has no back, so it uses (1) or a single sheet.

Every print screen shows: *"Print at 100% / Actual size, flip on long edge."* Card images are rendered at 300 DPI before placing them.

`PrintLayoutSpec { kind (id|passport), output, copies, frontPath, backPath? }` → `PdfBuilder.printSheet(spec)`.

---

## 9. Rewarded video (`google_mobile_ads`)

| Free | Unlocked by one video, per export |
|---|---|
| Scan, auto clean-up, all manual edits | **High quality** export (full resolution) |
| Share PDF / JPG at Standard quality | **PNG** export |
| Text from the current page | **Text from all pages** at once |
| Print layouts with 1–2 copies | Print layouts with **4, 6, 8** copies |

Rules:
- `RewardGate.unlock(feature)` returns `granted / cancelled / offline`.
- **No internet** → show "Needs internet for the video" and keep the free options working.
- **Ad fails to load** (no fill or error) → grant anyway. Good UX, and safe with AdMob policy.
- Ads are preloaded when the Share sheet or Print screen opens, so there's no wait.
- **Consent:** Google UMP consent form on first launch (required for EEA/UK users).
- **Dev flavor** uses Google's test ad unit IDs only.

---

## 10. Text recognition (OCR)

- `google_mlkit_text_recognition`, **Latin script model** (English and other Latin-script languages). Runs on the device, offline. **No Urdu.**
- It reads the *processed* page (after crop and filter), which gives better accuracy.
- The result is cached in `ScanPage.ocrText` and cleared when that page's edits change.
- UI: a `TextField` (editable) with the system selection toolbar (cut / copy / select all), plus buttons for Cut, Share .txt and Copy all.
- "All pages" joins pages with a `--- Page n ---` separator. It's gated by video (§9).

---

## 11. Export, share and save

| Action | How |
|---|---|
| Share PDF | Render pages at the chosen quality → `PdfBuilder.fromPages` → temp file → `share_plus` |
| Share JPG / PNG | Render each page → temp files → `share_plus` (multiple files) |
| Save images to phone | `gal` (saves to Photos/Gallery, no storage permission) |
| Save PDF to phone | `file_picker` `saveFile` (system save dialog: Downloads, Drive, iCloud, etc.) |
| Page size | A4 · Letter · Fit to image |
| Quality | Standard (long edge ≈ 2000 px, JPEG 85) · High (original, JPEG 95) |
| File name | Defaults to the document title, editable in the sheet |

Temp export files are deleted on the next app start. Each export writes an `Activity` row, which feeds Home.

---

## 12. Shared widgets (DRY)

| Widget | Used on |
|---|---|
| `AppScaffold(nav: bool, forceDark: bool)` | every screen |
| `AppTopBar` (back / close + title + subtitle + actions) | all inner screens |
| `AppBottomNav` + `ScanFab` | Home, Settings |
| `DocumentTile` (thumb, title, meta, activity line, ⋮) | Home, search |
| `PageThumb` (selected ring, number badge) | Viewer strip, Enhance, Batch review |
| `QuickActionTile` | Home |
| `SegmentedPills<T>` | Text tabs, Print outputs, Settings theme, Share format |
| `OptionChip` / `OptionCard` (with optional `VideoBadge`) | Share sheet, Print copies |
| `LabeledSlider` | Enhance |
| `ToolbarAction` (icon + label) | Adjust edges, Viewer |
| `PrimaryButton` / `SecondaryButton` | everywhere |
| `AppBottomSheet` | Share sheet, document ⋮ menu |
| `AppDialog` | Unlock, delete confirm, rename |
| `EmptyState`, `ErrorView`, `ProgressOverlay` | Home empty, failures, export/OCR progress |
| `AppIcon(AppIcons.x)` | one SVG registry for all icons |

Rule: a widget used on 2+ screens lives in `shared/widgets`.

---

## 13. Storage

```
<app documents>/flashdox/
  docs/<docId>/original/<pageId>.jpg
  docs/<docId>/processed/<pageId>.jpg      # cache
  docs/<docId>/thumb/<pageId>.jpg          # cache
<temp>/flashdox_export/                    # cleared on launch
```

Drift tables: `documents`, `pages`, `activities`.
"Clear temporary files" deletes export temp files plus the processed/thumb caches; they rebuild on demand.
Deleting a document removes its folder and rows, after a confirm dialog.

---

## 14. Theme

- **Font:** Manrope (400–800).
- **Accent:** Flash Amber `#FFC233`, with text on amber `#1B1400`.

| Token | Dark | Light |
|---|---|---|
| bg | `#0F1012` | `#F5F5F2` |
| surface | `#1A1C20` | `#FFFFFF` |
| surface2 | `#24272D` | `#EEEEEA` |
| border | `#2E3239` | `#E1E1DC` |
| text | `#F3F3F1` | `#15171A` |
| muted | `#A6AAB2` | `#5C6169` |
| accentText (links, labels) | `#FFC233` | `#8A5A00` |
| accentSoft | amber 14% | amber 22% |

- Tokens live in a `ThemeExtension` (`AppColors`) so widgets never hard-code colours.
- Camera, Adjust edges and Enhance always use the dark theme (`forceDark`).
- The default theme is **System**.
- Radii: 10 / 14 / 16 / 24 / pill. Spacing: 4-point scale. Tap targets ≥ 44 dp.

---

## 15. Platform setup

| Item | Note |
|---|---|
| Platforms | Android + iOS, English only (`gen-l10n` set up from day 1 anyway) |
| Permissions | Camera only. Gallery uses the system photo picker; saving uses `gal` / the save dialog. **No storage permission.** |
| Share-in | Android intent filters for `image/*`; iOS Share Extension (`receive_sharing_intent`) |
| Min versions | Check the minimums required by `opencv_dart`, ML Kit and `google_mobile_ads` at setup, and set them in Gradle / Podfile |
| App size | `opencv_dart` adds noticeable size. Build split APKs / App Bundle, and include only the OpenCV modules we use if the package allows it |
| Flavors | `dev` (test ads, debug logs) · `prod` |
| Crash reports | Firebase Crashlytics |

---

## 16. Testing

- **Unit:** `ImageProcessor` steps on a set of sample photos (receipts, CNIC, A4, dark/skewed shots); `PrintLayoutCalculator` positions (incl. duplex mirroring); repositories with an in-memory Drift DB.
- **Bloc:** `bloc_test` for ScanSession, PageEditor, Export, Reward.
- **Widget / golden:** shared widgets and key screens in light + dark.
- **Integration:** capture → adjust → enhance → share PDF; ID card → print layout 4 copies → PDF.
- **Manual print test:** print the duplex PDF on a real printer and check that the backs line up.

---

## 17. Milestones

| # | Milestone | Done when |
|---|---|---|
| 0 | Setup | Flavors, DI, router + shell, theme tokens, lints, CI, icon registry, splash |
| 1 | Shared widgets | §12 widgets with light/dark goldens |
| 2 | Data layer | Drift schema, FileStore, DocumentRepository, activity log |
| 3 | Camera + import | 4 modes, flash, capture, gallery/files import, share-in |
| 4 | Image pipeline | Edge detection, warp, 5 filters, sliders, isolate worker, tests on sample photos |
| 5 | Editor UI | Adjust edges (corners + magnifier), Enhance, apply to all, compare |
| 6 | Home + Viewer | Recent activity, rename, reorder, add/delete pages |
| 7 | Export | PDF + JPG/PNG, quality, page size, share, save to phone |
| 8 | Print layouts | ID + passport, 3 outputs, 1–8 copies, duplex mirroring, real-size PDF |
| 9 | OCR | Page + all pages, editable text, cut/copy, share .txt |
| 10 | Rewarded video | UMP consent, gate, fail-open, offline handling |
| 11 | Settings + polish | Theme, defaults, storage, policy/FAQ, empty/error states, accessibility, store assets |

---

## 18. Notes for your Figma file

You said you'll rename these yourself. If you keep the Figma file in sync with the new canvas:

- **Remove:** Manager, Converter/Tools, File Reader, To Word, sign-up, folder grid, Favorites, Trash, per-app share buttons.
- **Rename for one consistent name per thing:** "Flash Cam" → **Scan** (or "Camera") everywhere; "Recent Files" → **Recent activity**.
- **Fix typos in component names:** *Nevigation, Seating Header, Albhabetically, Templete, Fevorite, Lite Mode*. Rename `Variant11`, `Component 44`, `Frame 78`, etc. to real names.
- **Settings:** the second "Privacy & Policy" row becomes **FAQ** (already done on the canvas).
- **Icons:** export as SVG on a 24 px grid, one file per icon (no separate 20/21/30 copies).

---

## 19. Light mode — recommendation

**Yes, ship light mode in v1, defaulting to the phone's System setting.**
- Many users run their phones in light mode, and a dark-only app looks out of place in daylight.
- The cost is small: every screen already reads colours from theme tokens, so light mode is a second token set, not new screens.
- Camera, Adjust edges and Enhance stay dark in both themes, so document photos stay easy to judge.
