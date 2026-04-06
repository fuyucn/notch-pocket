# Changelog

All notable changes to Notch Pocket will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/fuyucn/notch-pocket/compare/v0.3.0...HEAD
[v0.3.0]: https://github.com/fuyucn/notch-pocket/compare/v0.2.0...v0.3.0
[v0.2.0]: https://github.com/fuyucn/notch-pocket/compare/v0.1.0...v0.2.0
[v0.1.0]: https://github.com/fuyucn/notch-pocket/releases/tag/v0.1.0
