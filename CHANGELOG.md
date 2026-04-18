# Changelog

All notable changes to Notch Pocket will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.4.2] — 2026-04-17

Continuing `plan-7-airdrop-drop-target`.

### Added
- **Popping pill doubles as a minimized shelf indicator**. When the shelf has items and the panel isn't opened, the popping pill stays visible showing a tray icon, up to 3 file thumbnails, and a count badge — a persistent "files are here" reminder. Tap it to open the full shelf.
- `NotchViewModel.requestClose()` — smart close that returns to the popping pill when the shelf has items, otherwise fully hides. Used by click-outside, the × button, and the Cmd+Shift+D keyboard shortcut.
- `NotchViewModel.forceClose()` — unconditional `.closed` for quit / teardown paths.
- App launch now shows the popping pill automatically if restored shelf content is present.

### Changed
- `PreActivationBarView` forks its content on `isFileDragging`:
  - `true` → existing "Drop here" drag affordance
  - `false` → tray icon, mini thumbnails (first 3 items, + "+N" overflow), count badge
- `NotchDropForwarder` dependency on `NotchViewModel.isDragInside` now also drives the popping pill's visual mode (drag preview vs. idle reminder).

### Removed
- The short-lived `.minimized` status case introduced earlier in the session. Folded into `.popping` to keep the state machine at 3 cases — less duplication across view, view-model, and tests.

## [v0.4.1] — 2026-04-17

Plan 7 (AirDrop + drag-out) and plan 8 (storage modes) (`plan-7-airdrop-drop-target`)

### Added
- **AirDrop block**: square action button in the opened shelf. Tap sends every shelf file via `NSSharingService.sendViaAirDrop`; drag-drop a file directly onto the button to AirDrop without shelving it. Drag-over highlights the button.
- **Drag-out from the shelf**: drag a single cell/row to Finder or any app to copy the file out. New **All** pill at the top-right of the file area starts a multi-item drag for the whole shelf.
- **Storage mode setting** (`Reference` / `Local copy`, default `Reference`):
  - Reference — shelf stores a bookmark to the original file; zero extra disk; drag-out hands Finder the original URL so a plain drop is a real filesystem move.
  - Local copy — shelf copies the file into `~/Library/Application Support/NotchPocket/shelf/`; drag-out uses `NSFilePromiseProvider` so Finder never touches our private directory.
- **Remove on drag-out** toggle (default on): after a successful drag-out the shelf entry is dropped. Independent of the macOS Option key, which still controls copy/move on the receiving side.
- Hover-revealed `×` on shelf cells and list rows for explicit per-item removal.

### Changed
- Shelf storage directory moved from `~/Library/Caches/com.dropzone.app` to `~/Library/Application Support/NotchPocket/shelf` so Finder can perform file operations on local-copy items without `NSFileWriteUnknownError` (-8058).
- Shelf files are always copied (no more hard-links); the shelf holds an independent inode per item.
- Drop de-duplication (canonical `originalURL` match) re-instated after the plan-6 rewrite dropped it.
- Opened shelf no longer auto-dismisses after drops — it stays open until the user clicks outside the panel or presses the close button.
- AppKit `NSWindow.didResignKey` drives click-outside-to-close.

### Removed
- `EventMonitor`, `EventMonitors`, and `PermissionsManager` are gone. The app no longer needs Input Monitoring permission — drag-in activation flows through `NotchDropForwarder` (NSDraggingDestination in our own window) and panel hover uses the `NSPanel` key-window lifecycle. Settings window no longer shows the "Permissions" section.
- `releases/` directory is now `.gitignore`d except for its README.

### Fixed
- File name preserved on drag-out for `.app` bundles and plain-text (`.md`) files — previously Finder fell back to the UTI's localized description (e.g. "Markdown text file.md").

## [v0.4.0] — 2026-04-17

Plan 6: Drag pre-activation bar & shelf list redesign (`plan-6-preactivation-and-shelf-list`)

### Added
- **Dynamic-Island-style notch panel.** `NotchShape` renders a concave top / rounded bottom silhouette that wraps the physical notch. Shape radii and panel size animate together via SwiftUI spring transitions between closed / popping / opened states. Inspired by [Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island).
- **Drag pre-activation bar** (`.popping`). A narrow 380×120 "Drop here" pill appears below the notch when a file drag enters the top-of-screen hover trigger rect, previewing the dragged filename (+N for multiples) and current shelf count badge on the notch's right shoulder.
- **Opened shelf panel** (`.opened`). Wider 680×360 panel with vertical **ShelfListView** (rows show file icon, name, age, and app / type / size capsule tags) or horizontal **ShelfContainerView** thumbnails — switchable in place via a view-toggle button on the notch's right shoulder.
- **View-mode + close** controls on the notch right shoulder replace the separate header row.
- **PermissionsManager** + Settings UI "Permissions" section — explicit Input Monitoring status display with a Grant button that prompts or falls back to opening System Settings.
- **Settings / Shelf section:** segmented pickers for `Shelf view` (List / Thumbnails) and `Stay expanded` (persistent / auto-hide after drop).
- `ShelfItem` gained `sourceAppName` (from pasteboard `com.apple.pasteboard.source-app-bundle-identifier`) and `fileExtension` metadata.
- `markDropped(stickyFor:)` keeps the shelf visible for a short window after a drop so users see what landed.
- Menu-bar "Show Shelf" item now opens the shelf again.

### Changed
- **Complete panel architecture rewrite.** `DropZonePanel` / `HoverDetectionPanel` / `GlobalDragMonitor` / `DragDestinationView` / `ScreenDetector` retired in favor of a NotchDrop-style always-visible transparent `NotchPanel` backed by a Combine `EventMonitors` bus and a single `NotchViewModel` state machine. The panel is `ignoresMouseEvents = true` when idle, so clicks pass through to apps below; becomes interactive when a file drag enters.
- `NotchDropForwarder` is a dedicated overlay `NSView` that receives `NSDraggingDestination` callbacks independently of the SwiftUI hosting view.
- Pre-activation / opened panels now top-align to the notch so the visual wraps the physical cutout instead of floating below it.
- Shelf row padding and layout tightened.

### Fixed
- Panel window height expanded so `.opened` content no longer draws outside the NSHostingView frame.

### Known
- Generic `.leftMouseDragged` events still pop the panel even for non-file drags (window moves, text selection). Tightening this is a follow-up.

## [v0.3.0] — 2026-04-06

Plan 4: Notch positioning fix & release automation (`plan-4-notch-positioning-fix`)

### Fixed
- Panel Y-coordinate now anchors to screen top edge (`notch.maxY`) instead of notch bottom
- Window level reduced from `CGShieldingWindowLevel` to `.popUpMenu` so drag-and-drop works
- Drag destination view properly accepts file drops again
- Visual effect material upgraded from `.hudWindow` to `.popover` for better translucency
- Click-through on drag destination view (`hitTest` returns `nil`)
- Drag destination view moved to topmost in view hierarchy for reliable drop events

### Changed
- Refined notch geometry calculations for accurate panel positioning
- Updated panel and drag destination tests to match corrected behavior

### Added
- GitHub Actions release workflow (triggered by version tags)
- `release-package.sh` script for building and packaging `.app` bundles
- `releases/` directory for release artifacts

## [v0.2.0] — 2026-04-06

Plans 2–3: Notch detection and file shelf UI (`plan-3-file-shelf-ui`)

### Added
- Global drag monitor for system-wide drag event tracking
- Status bar controller with file count badge and context menu
- File shelf UI with horizontal scrolling thumbnails and drag-out support
- Async thumbnail generation via QuickLook with fallback system icons
- Settings management with `@AppStorage`-backed preferences
- Preferences UI (SwiftUI settings window)
- Global keyboard shortcut registration via Carbon Events API
- Full test suite for settings, keyboard shortcuts, and all modules

### Changed
- Wired settings and keyboard shortcuts into app lifecycle
- Renamed user-visible strings from "DropZone" to "Notch Pocket"
- Updated README, CLAUDE.md, and DESIGN.md for Plans 1–3

### Fixed
- Hardened `.gitignore` with security and credential patterns

## [v0.1.0] — 2026-04-06

Plan 1: Project scaffolding and core modules (`plan-1-project-setup`)

### Added
- Swift Package Manager project structure (macOS 14+, Swift 6.0)
- `DropZoneLib` library target with core modules:
  - `NotchGeometry` — notch rect and activation zone computation
  - `ScreenDetector` — notch/non-notch screen detection with display change observation
  - `DropZonePanel` — NSPanel subclass for floating panel over the notch
  - `FileShelfManager` — temp file storage with hard-link optimization and auto-expiry
  - `DragDestinationView` — NSDraggingDestination implementation for file drops
  - `AppDelegate` — app lifecycle wiring
- `DropZone` executable target with `main.swift` entry point
- Project documentation: README, CLAUDE.md, DESIGN.md, PLANS.md
- `.gitignore` with Swift/Xcode/macOS patterns

[Unreleased]: https://github.com/fuyucn/notch-pocket/compare/v0.4.2...HEAD
[v0.4.2]: https://github.com/fuyucn/notch-pocket/compare/v0.4.1...v0.4.2
[v0.4.1]: https://github.com/fuyucn/notch-pocket/compare/v0.4.0...v0.4.1
[v0.4.0]: https://github.com/fuyucn/notch-pocket/compare/v0.3.0...v0.4.0
[v0.3.0]: https://github.com/fuyucn/notch-pocket/compare/v0.2.0...v0.3.0
[v0.2.0]: https://github.com/fuyucn/notch-pocket/compare/v0.1.0...v0.2.0
[v0.1.0]: https://github.com/fuyucn/notch-pocket/releases/tag/v0.1.0
