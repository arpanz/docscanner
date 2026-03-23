
Here's the complete, revised blueprint with every tweak from our discussion folded in.
Flutter Doc Scanner — Revised Blueprint
Core Philosophy
Minimal UI, maximum speed. Every screen does one thing well. Scan → review → organize → export. No feature bloat, no ceremony.
Pages (3 + 1 Modal)
The original 4-page plan collapses Crop & Enhance into a modal bottom sheet, reducing navigation hops and keeping the camera always in the background.
1. Camera / Scan Page (Home)
Full-screen camera preview with zero chrome
flutter_doc_scanner handles real-time edge detection, auto-capture, and perspective correction natively via ML Kit (Android) and VisionKit (iOS) pub
Single floating capture button, bottom center
Scrollable thumbnail strip at bottom showing current batch
Flash toggle + gallery import in top bar (minimal icons)
Auto-capture: snaps when edges are stable for ~0.5s developers.google
Wrap the entire preview in RepaintBoundary — prevents edge overlay repaints from triggering full widget tree rebuilds
2. Crop & Enhance (Modal Bottom Sheet, not a full page)
Slides up after capture — camera stays live in the background
Draggable corner handles on the detected quadrilateral
Filter chips: Original | B&W | Sharpen | Magic (auto-enhance)
ML Kit natively handles shadow removal, stain cleanup, and filter application developers.google
Rotate left/right, pinch-to-zoom for precision
"Retake" dismisses the sheet; "Done" saves and returns to camera
3. Document Manager Page
Grid view of scanned documents (thumbnail of first page)
Each card: title (auto-named via OCR), page count, date, file size
Mini-FAB in the top-right corner, not bottom — avoids conflict with swipe-to-delete gestures on Android
Long-press for multi-select (delete, merge, share)
Search bar at top — searches OCR-extracted text via Drift FTS5
Sort by: Date / Name / Size
Thumbnails are precomputed in a background isolate at save time, never lazily on first scroll
4. Document Viewer Page
PageView.builder with itemCount — never pre-build all pages in memory
Swipeable page-by-page view
Reorder pages via drag handle
Add more pages to an existing document
Share/export button (PDF, JPG, PNG)
Page count indicator
UI / Design System
Theme: Material 3, monochrome palette — white background, dark grey text, single accent (deep blue or teal). No gradients, no shadows except on FAB.
Typography: Google Fonts Inter or Plus Jakarta Sans — clean, geometric, highly legible.
Animations:
Hero animation: thumbnail → viewer transition
Scale animation on capture button press
Shimmer placeholder while processing
Modal sheet slide-up on capture confirm
Key principles:
No bottom nav bar — the camera IS the home screen
Gesture-first: swipe to delete, pinch to zoom, drag to reorder
Status feedback via snackbars, never dialogs
Dark mode from day one (invert the monochrome palette)
Package Stack
Purpose	Package	Why
Edge detection + crop + filters	flutter_doc_scanner	Wraps ML Kit (Android) + VisionKit (iOS); handles detection, crop, filters, shadow/stain removal natively pub
Camera (fallback / custom UI)	camera (official)	Full control over preview stream if you want custom chrome
Image processing	image (dart)	Pure Dart crop/rotate for any post-processing outside ML Kit
Compression	flutter_image_compress	JPEG at 85% quality before saving to disk
PDF generation	pdf + printing	Lightweight, no native deps
Local database	drift	Type-safe SQL, compile-time validation, best-in-class migrations, FTS5 for OCR search quashbugs
File storage	path_provider + raw file I/O	Images as compressed JPEGs on disk, never blobs in DB
State management	riverpod	Compile-safe, great async/isolate integration
Permissions	permission_handler	Camera + storage
Share/export	share_plus	Native share sheet
OCR (auto-naming + search)	google_mlkit_text_recognition	On-device, offline, no network needed
Performance Strategy
Image Pipeline
flutter_doc_scanner does edge detection on the live preview stream internally — you never touch raw frame data pub
Capture at native resolution; process perspective correction on the full-res image only once, after the user confirms corners
Compress to JPEG at 85% quality via flutter_image_compress immediately — ~60–70% smaller than PNG, visually lossless
All filter application and OCR runs in compute() isolates — the UI thread is never blocked
Process at max 1500px on the longest edge for storage (sufficient for A4 at 150 DPI)
Thumbnail Strategy
Generate 200px thumbs immediately on save, in a background isolate
Store as page_001_thumb.jpg alongside the full-res image
Grid view uses ResizeImage provider pointing to the thumb file — never downscales originals at runtime
imageCache.clear() after processing a batch to prevent memory bloat
App-Level Speed
Precache the camera controller on app start — viewfinder is instant on open
PageView.builder in the viewer — only the current + adjacent pages are in memory androidcoding
Drift reactive streams (watchSingle, watch) — UI rebuilds only when data actually changes androidcoding
Riverpod select to watch only specific fields, preventing unnecessary widget rebuilds
RepaintBoundary on the camera preview widget
Build-Time
--split-debug-info and --obfuscate for release builds
--tree-shake-icons to strip unused Material icons
Profile with Flutter DevTools timeline, specifically the scan → save flow
Data Architecture
/app_data/
  /documents/
    /{doc_id}/
      meta.json            // fallback / export reference
      page_001.jpg         // full resolution (max 1500px long edge)
      page_001_thumb.jpg   // 200px thumbnail
      page_002.jpg
      page_002_thumb.jpg
      ...
  /temp/                   // wiped on app start
    capture_raw.jpg
    crop_preview.jpg
Drift schema stores all metadata — images stay on disk, never as blobs in the DB: quashbugs
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()(); // auto-filled via OCR
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get pageCount => integer()();
  TextColumn get tags => text().nullable()();
  TextColumn get ocrText => text().nullable()(); // FTS5 searchable
  TextColumn get folderPath => text()(); // path on disk
}
Drift's FTS5 extension enables full-text search over ocrText in microseconds without any custom indexing logic. quashbugs
Suggested Extras (Optional, Low-Scope)
Auto-naming via OCR: On save, run google_mlkit_text_recognition in an isolate on page 1, extract the first recognizable line as the document title — zero UI overhead, makes the manager actually useful
Auto-brightness hint: If the frame is underexposed, pulse the flash icon
Batch mode: Scan multiple pages without leaving the camera, review all at once before saving
Quick share: Long-press a document card to immediately share as PDF
Android home screen widget: Opens directly to camera
What to Skip (Keeps It Minimal)
Cloud sync — auth, server costs, and sync conflicts are a separate product
Annotation/drawing tools — scope creep for v1
Folder hierarchies — flat list + search is faster and simpler
Watermarking — nobody wants it in a personal scanner
In-app PDF viewer — use the system share sheet and let the OS handle it
Here's the complete expanded blueprint covering the Flutter project folder structure, full UI system, and component-level detail.
Flutter Doc Scanner — Full Blueprint (Expanded)
Project Folder Structure
Feature-first is the right approach here — each screen owns its own data, logic, and widgets. Nothing bleeds across features unless it lives in core/ or shared/. pravux
lib/
├── main.dart
├── app.dart                    // MaterialApp, theme, router setup
│
├── core/
│   ├── constants/
│   │   ├── app_colors.dart     // seed color, surface tokens
│   │   ├── app_spacing.dart    // spacing scale (4, 8, 12, 16, 24, 32)
│   │   └── app_strings.dart    // all user-facing strings
│   ├── theme/
│   │   ├── app_theme.dart      // lightTheme + darkTheme
│   │   ├── text_styles.dart    // named text style references
│   │   └── component_themes.dart // FAB, card, chip overrides
│   ├── router/
│   │   └── app_router.dart     // GoRouter config
│   └── utils/
│       ├── file_utils.dart     // path helpers, temp dir cleanup
│       ├── image_utils.dart    // resize, compress helpers
│       └── date_utils.dart
│
├── shared/
│   ├── widgets/
│   │   ├── shimmer_placeholder.dart
│   │   ├── doc_thumbnail.dart      // reused in grid + viewer
│   │   ├── snackbar_service.dart
│   │   └── drag_handle.dart
│   └── services/
│       ├── ocr_service.dart        // wraps google_mlkit_text_recognition
│       ├── pdf_service.dart        // wraps pdf + printing
│       └── compress_service.dart   // wraps flutter_image_compress
│
├── features/
│   ├── camera/
│   │   ├── data/
│   │   │   └── camera_repository.dart
│   │   ├── providers/
│   │   │   └── camera_provider.dart  // Riverpod
│   │   └── presentation/
│   │       ├── camera_page.dart
│   │       ├── widgets/
│   │       │   ├── capture_button.dart
│   │       │   ├── thumbnail_strip.dart
│   │       │   └── flash_toggle.dart
│   │       └── sheets/
│   │           └── crop_enhance_sheet.dart  // modal bottom sheet
│   │
│   ├── manager/
│   │   ├── data/
│   │   │   └── document_repository.dart
│   │   ├── providers/
│   │   │   └── manager_provider.dart
│   │   └── presentation/
│   │       ├── manager_page.dart
│   │       └── widgets/
│   │           ├── doc_card.dart
│   │           ├── sort_bar.dart
│   │           └── search_bar.dart
│   │
│   └── viewer/
│       ├── providers/
│       │   └── viewer_provider.dart
│       └── presentation/
│           ├── viewer_page.dart
│           └── widgets/
│               ├── page_item.dart
│               ├── reorder_handle.dart
│               └── export_sheet.dart
│
└── database/
    ├── app_database.dart       // Drift database class
    ├── tables/
    │   ├── documents_table.dart
    │   └── pages_table.dart
    └── daos/
        ├── documents_dao.dart
        └── pages_dao.dart
App-Wide File Storage Layout
/app_data/
  /documents/
    /{doc_id}/
      page_001.jpg
      page_001_thumb.jpg     // 200px, precomputed at save time
      page_002.jpg
      page_002_thumb.jpg
  /temp/                     // wiped on every cold start
    capture_raw.jpg
    crop_preview.jpg
Never store image blobs in Drift — only paths, metadata, and OCR text. quashbugs
Design System
Color & Theme
Use a single seed color with ColorScheme.fromSeed() — M3 generates a full tonal palette (light + dark) automatically from it. You don't manually define every color. christianfindlay
// core/theme/app_theme.dart
const seedColor = Color(0xFF1A56DB); // deep blue

final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  ),
  textTheme: GoogleFonts.interTextTheme(),
  useMaterial3: true,
);

final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  ),
  textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  useMaterial3: true,
);
Note: background, onBackground, and surfaceVariant are deprecated in current M3 — use surface, onSurface, and surfaceContainerHighest instead. docs.flutter
Spacing Scale
Define a single spacing file and reference it everywhere — never hardcode padding values: pravux
// core/constants/app_spacing.dart
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 24;
  static const double xl = 32;
}
Typography
Stick to 4 named styles across the whole app. Inter handles all of them cleanly:
Role	Usage	Style
titleLarge	Document titles in grid	18sp, SemiBold
bodyMedium	Metadata (date, size, page count)	13sp, Regular
labelSmall	Filter chip labels, page counter	11sp, Medium
displaySmall	Empty state heading	28sp, Bold
Page-by-Page UI Detail
Camera Page
┌─────────────────────────────────┐
│  [Flash ⚡]           [Gallery] │  ← 44px tap targets, icon-only
│                                 │
│                                 │
│   ┌ - - - - - - - - - - - ┐    │
│   |  (edge detection       |    │  ← animated path, teal accent stroke
│   |   quadrilateral)       |    │
│   └ - - - - - - - - - - - ┘    │
│                                 │
│                                 │
│  [thumb][thumb][thumb] ───────  │  ← horizontal scrollable strip, 56px tall
│         ◉                       │  ← capture button, 72px circle
└─────────────────────────────────┘
Status bar is transparent, camera bleeds full-screen
Edge detection overlay drawn with CustomPainter — four corner handles + connecting lines in the seed accent color, 40% opacity fill
Capture button: outer ring pulses subtly when edges are detected and stable (scale 1.0 → 1.05, 300ms)
Thumbnail strip uses ListView.builder — never pre-builds all items
RepaintBoundary wraps the entire camera preview
Crop & Enhance Sheet
┌─────────────────────────────────┐
│          [drag pill]            │
│  ┌─────────────────────────┐   │
│  │                         │   │
│  │    document preview     │   │  ← full-res, pinch-to-zoom
│  │   ◉───────────────◉     │   │  ← draggable corner handles
│  │   │               │     │   │
│  │   ◉───────────────◉     │   │
│  └─────────────────────────┘   │
│                                 │
│  [Original] [B&W] [Sharpen] [✨] │  ← FilterChip row
│  [↺ Rotate]            [↻ Rotate]│
│                                 │
│  [Retake]              [Done →] │
└─────────────────────────────────┘
Sheet height: 85% of screen — enough room for the document + controls
Corner handles: 24px circle, filled accent color, GestureDetector with onPanUpdate
Filter chips use ChoiceChip — single selection, selected state uses colorScheme.primaryContainer
Filters applied in a compute() isolate — show a shimmer over the preview while processing
"Done" triggers thumbnail precompute in background + OCR auto-naming, both in separate isolates
Document Manager Page
┌─────────────────────────────────┐
│  Doc Scanner          [+ New]   │  ← title left, mini-FAB top-right
│  ┌─────────────────────────┐   │
│  │ 🔍 Search documents...  │   │  ← persistent search bar
│  └─────────────────────────┘   │
│  Date ▼  |  Name  |  Size      │  ← sort chips, inline
│                                 │
│  ┌────────┐  ┌────────┐        │
│  │[thumb] │  │[thumb] │        │  ← 2-column grid
│  │Invoice │  │Resume  │        │  ← auto-named via OCR
│  │3 pages │  │1 page  │        │
│  │Mar 22  │  │Mar 21  │        │
│  └────────┘  └────────┘        │
└─────────────────────────────────┘
Grid: SliverGrid with crossAxisCount: 2, childAspectRatio: 0.78
Cards: InkWell with 12px border radius, subtle surfaceContainerHighest background, no elevation
Long-press enters multi-select mode — cards get a teal checkmark overlay, top bar swaps to action bar (delete, share, merge)
Empty state: large centered illustration + "Tap + to scan your first document" in displaySmall
Swipe-to-delete: Dismissible widget, red Icons.delete_outline background revealed on swipe
Document Viewer Page
┌─────────────────────────────────┐
│  ←  Invoice_Mar22    [⋮ Export] │
│                                 │
│  ┌─────────────────────────┐   │
│  │                         │   │
│  │       Page content      │   │  ← PageView.builder, swipeable
│  │                         │   │
│  └─────────────────────────┘   │
│         Page 2 of 5            │  ← dot indicator + text counter
│                                 │
│  ☰  Reorder   +  Add Pages     │  ← bottom action strip
└─────────────────────────────────┘
PageView.builder — only current ± 1 pages in memory at any time
Export sheet (bottom sheet): chips for PDF / JPG / PNG, then native share sheet via share_plus
Reorder mode: ReorderableListView overlays the viewer showing all page thumbs as draggable tiles
Page indicator: AnimatedSmoothIndicator (from smooth_page_indicator) — dots scale on active
Riverpod Provider Map
AppDatabase (Drift)
    └── DocumentsDao
            └── documentsProvider (StreamProvider) → manager_page
            └── documentByIdProvider → viewer_page

CameraController
    └── cameraControllerProvider (StateNotifierProvider) → camera_page

ScanSessionProvider (StateNotifierProvider)
    └── holds current batch of captured images → thumbnail_strip + crop sheet

ProcessingProvider (FutureProvider.family)
    └── runs compress + OCR + thumb generation in isolates
Component Themes (Override in app_theme.dart)
Override only what deviates from M3 defaults — don't over-specify: christianfindlay
cardTheme: CardTheme(
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  color: colorScheme.surfaceContainerHighest,
),
chipTheme: ChipThemeData(
  shape: StadiumBorder(),
  side: BorderSide.none,
),
bottomSheetTheme: BottomSheetThemeData(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  showDragHandle: true,
),
floatingActionButtonTheme: FloatingActionButtonThemeData(
  shape: CircleBorder(), // camera page capture button
),
Animations Checklist
Trigger	Animation	Duration
Thumbnail → viewer open	Hero on doc thumbnail	300ms
Capture button on edge lock	Scale 1.0 → 1.05 → 1.0	300ms
Crop sheet appears	Slide up (DraggableScrollableSheet)	280ms
Filter apply	Shimmer over preview	While isolate runs
Multi-select enter	Checkmark fade-in on cards	150ms
Page swipe	Default PageView physics	—
Keep all animations under 350ms — anything longer feels sluggish on a utility app. miquido
