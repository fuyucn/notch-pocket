# Notch Pocket

> **Note:** This is an AI-generated side project — built collaboratively with AI assistance.

A macOS app that transforms your MacBook's notch into a temporary file shelf — a pocket right in the notch — enabling frictionless cross-window, cross-space file transfers via drag-and-drop.

![Version](https://img.shields.io/badge/version-v0.4.0-blue)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Notch as a drop zone** — Drag files onto the notch area to temporarily shelve them, then freely switch contexts
- **Drag out to retrieve** — Hover over the notch to expand the shelf, then drag files to their destination
- **Multi-file batch drop** — Drop multiple files at once; all are shelved with thumbnail previews
- **Auto-expire cleanup** — Shelved files automatically expire after a configurable period (default: 1 hour)
- **Notch & non-notch support** — Works on MacBooks with a notch and falls back to a floating pill on older Macs or external displays
- **Multi-monitor** — Detects screen configurations and repositions the panel on display changes
- **Keyboard shortcut** — Toggle the shelf with a configurable global hotkey (default: `⌘ + Shift + D`)
- **Settings panel** — Configure expiration time, storage limits, launch at login, and more
- **Menu bar integration** — Quick access via a status bar icon with file count badge

<!-- ## Screenshots

> Screenshots will be added after the first public release.

| Drop zone expanded | Shelf with files | Settings |
|---|---|---|
| ![Drop zone](screenshots/dropzone-expanded.png) | ![Shelf](screenshots/shelf-view.png) | ![Settings](screenshots/settings.png) | -->

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ (full installation, not just Command Line Tools)

## Installation

### Build from Source

```bash
git clone https://github.com/fuyucn/dropzone.git
cd dropzone/DropZone

# Debug build
swift build

# Release build
swift build -c release
```

The built executable is located at `.build/release/DropZone`.

### Xcode

Open `DropZone/Package.swift` in Xcode, select the `DropZone` scheme, and run.

## Usage

1. **Launch** — Run Notch Pocket. A menu bar icon appears in the status bar.
2. **Shelve files** — Start dragging any file. The notch area activates automatically. Drop the file onto it.
3. **Switch context** — Navigate to your target app, folder, or Space. Your hands are free.
4. **Retrieve files** — Hover over the notch to expand the shelf. Drag your file out to the destination.
5. **Manage** — Right-click the menu bar icon to clear the shelf, open settings, or quit.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ + Shift + D` | Toggle shelf visibility (configurable) |
| Hover over notch | Expand shelf to see thumbnails |

### Menu Bar

The status bar icon shows the current shelved file count. Click it to access:

- **Show Shelf** — Expand the shelf panel
- **Settings** — Open the preferences window
- **Clear All** — Remove all shelved files
- **Quit** — Exit Notch Pocket

## Configuration

Access settings via the menu bar icon → **Settings**, or use the keyboard shortcut.

| Setting | Default | Range |
|---------|---------|-------|
| Auto-expire duration | 1 hour | 15 min – 24 hours |
| Max shelf items | 50 | 10 – 200 |
| Max shelf storage | 2 GB | 500 MB – 10 GB |
| Launch at login | Off | On / Off |
| Global shortcut | `⌘ + Shift + D` | Customizable |

Files are stored temporarily in `~/Library/Caches/com.dropzone.app/shelf/`. Hard-links are used when files are on the same volume; cross-volume files are copied.

## Project Structure

```
dropzone/
├── CLAUDE.md                          # Development guidelines
├── DESIGN.md                          # Product design document
├── PLANS.md                           # Implementation roadmap
├── README.md                          # This file
├── DropZone/
│   ├── Package.swift                  # SPM config (macOS 14+)
│   ├── Info.plist                     # App metadata
│   ├── DropZone.entitlements          # App entitlements
│   ├── Sources/
│   │   ├── DropZone/
│   │   │   └── main.swift             # App entry point
│   │   └── DropZoneLib/               # Core library
│   │       ├── AppDelegate.swift              # App lifecycle, wiring
│   │       ├── DropZonePanel.swift            # Floating notch panel (NSPanel)
│   │       ├── DragDestinationView.swift      # Drop target (NSDraggingDestination)
│   │       ├── GlobalDragMonitor.swift        # System-wide drag detection
│   │       ├── FileShelfManager.swift         # File storage, expiry, capacity
│   │       ├── FileShelfView.swift            # Shelf grid UI (SwiftUI)
│   │       ├── FileThumbnailView.swift        # Thumbnail generation & display
│   │       ├── NotchGeometry.swift            # Notch rect & activation zone
│   │       ├── ScreenDetector.swift           # Screen detection & observation
│   │       ├── StatusBarController.swift      # Menu bar icon & menu
│   │       ├── SettingsManager.swift          # UserDefaults-backed settings
│   │       ├── SettingsView.swift             # Preferences UI (SwiftUI)
│   │       ├── SettingsWindowController.swift # Settings window management
│   │       └── KeyboardShortcutManager.swift  # Global hotkey (Carbon)
│   └── Tests/
│       └── DropZoneTests/             # Unit tests (Swift Testing)
│           ├── AppDelegateTests.swift
│           ├── DragDestinationViewTests.swift
│           ├── DropZonePanelTests.swift
│           ├── FileShelfManagerTests.swift
│           ├── FileShelfViewTests.swift
│           ├── FileThumbnailViewTests.swift
│           ├── GlobalDragMonitorTests.swift
│           ├── KeyboardShortcutManagerTests.swift
│           ├── NotchGeometryTests.swift
│           ├── ScreenDetectorTests.swift
│           └── SettingsManagerTests.swift
└── research/                          # Technical research notes
```

### SPM Targets

| Target | Type | Description |
|--------|------|-------------|
| `DropZoneLib` | Library | Core library with all business logic; imported by tests |
| `DropZone` | Executable | App entry point; depends on `DropZoneLib` |
| `DropZoneTests` | Test | Unit tests; depends on `DropZoneLib` |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.0 (strict concurrency) |
| UI | SwiftUI + AppKit |
| Build System | Swift Package Manager |
| Minimum OS | macOS 14 Sonoma |
| Testing | Swift Testing framework |
| Thumbnails | QuickLook (`QLThumbnailGenerator`) |
| Global Hotkey | Carbon Events API |
| Settings | UserDefaults via `@AppStorage` |

## Development

### Building

```bash
cd DropZone
swift build
```

### Running Tests

```bash
cd DropZone
swift test
```

> **Note**: Ensure `DEVELOPER_DIR` points to your Xcode installation, not Command Line Tools:
> ```bash
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```

### Branch Conventions

All development follows a branch-per-plan workflow. See [CLAUDE.md](CLAUDE.md) for full details.

- Feature branches: `plan-{number}-{short-description}`
- Hotfix branches: `hotfix-{number}-{short-description}`
- Merge to `main` via `--no-ff` after all tests pass

### Commit Messages

```
type: short description
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `build`

## Contributing

1. Fork the repository
2. Create a feature branch from `main` (`plan-N-description` or `feature/description`)
3. Make your changes, ensuring:
   - All existing tests pass
   - New functionality has corresponding tests
   - No compiler warnings introduced
   - Code builds in both Debug and Release
4. Submit a pull request with a clear description

### Code Style

- Follow Swift 6 strict concurrency conventions
- Use `@MainActor` for UI-bound code
- Prefer SwiftUI for views, AppKit for system-level integration
- Keep files focused — one primary type per file

## Roadmap

See [PLANS.md](PLANS.md) for the full implementation roadmap. Current status:

- [x] Plan 1 — Project setup & scaffolding
- [x] Plan 2 — Notch detection & floating panel
- [x] Plan 3 — Global drag monitoring, file shelf, thumbnails, drag-out, settings
- [ ] Plan 7 — File expiry & storage management
- [ ] Plan 8 — Animations & visual polish
- [ ] Plan 10 — Accessibility
- [ ] Plan 11 — Multi-monitor support
- [ ] Plan 12 — Edge cases & robustness
- [ ] Plan 13 — Performance optimization

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Inspired by:

- [NotchDrop](https://github.com/Lakr233/NotchDrop) — File shelf in the notch
- [TheBoringNotch](https://github.com/TheBoredTeam/boring.notch) — Architecture patterns
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — Notch UI framework
- [Atoll](https://github.com/Ebullioscopic/Atoll) — Animation patterns
