# DropZone — Project Guidelines

## Development Workflow

### Branch Management

**Main branch is protected.** Do not commit feature code, design documents, or any development work directly to `main`. The `main` branch only receives merges from verified feature/plan branches.

### Branch Naming Convention

Every plan or task must be developed on a dedicated branch:

```
plan-{number}-{short-description}
```

Examples:
- `plan-1-project-setup`
- `plan-2-notch-detection`
- `plan-3-file-shelf-ui`

Hotfix branches follow: `hotfix-{number}-{short-description}`

### Workflow Steps

1. **Create branch** — Branch off from `main` with the correct naming convention.
2. **Develop** — Implement the plan on the feature branch. Commit early and often with clear messages.
3. **Test** — All tests must pass before merging. Run the full test suite.
4. **Review** — Verify the implementation matches the plan requirements.
5. **Merge** — Merge the feature branch into `main` (no fast-forward: `git merge --no-ff`).
6. **Clean up** — Delete the feature branch after a successful merge.

### Merge Checklist

Before merging any branch into `main`, confirm:

- [ ] All existing tests pass (`swift test` in the `DropZone/` directory)
- [ ] New functionality has corresponding tests
- [ ] No compiler warnings introduced
- [ ] Code builds successfully in both Debug and Release
- [ ] Commit messages are clear and descriptive
- [ ] Branch is up to date with `main` (rebase or merge main into branch first)

### Commit Message Convention

```
type: short description

Optional longer description.
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `build`

### Version Tagging

Follow **Semantic Versioning** (`major.minor.patch`):

- **major** — Breaking changes or major milestones
- **minor** — New features, backward-compatible
- **patch** — Bug fixes, minor improvements

Tag format: `v0.1.0`, `v0.2.0`, `v1.0.0`

Tags are only applied on the `main` branch after a successful merge.

---

## Architecture Overview

### SPM Package Layout

The project uses Swift Package Manager with three targets:

```
DropZone/
├── Package.swift              # macOS 14+, Swift 6.0
├── Sources/
│   ├── DropZone/main.swift    # Executable entry point
│   └── DropZoneLib/           # Core library (all business logic)
└── Tests/
    └── DropZoneTests/         # Unit tests (Swift Testing)
```

- **`DropZoneLib`** — Library target containing all logic. This is what tests import.
- **`DropZone`** — Executable target, minimal `main.swift` that bootstraps the app.
- **`DropZoneTests`** — Test target using Swift Testing framework (`@Test`, `#expect`).

### Module Responsibilities

| File | Role |
|------|------|
| `AppDelegate.swift` | App lifecycle, wires all components together |
| `DropZonePanel.swift` | NSPanel subclass: floating panel over the notch, drag destination, shelf display, state machine |
| `DragDestinationView.swift` | NSView implementing NSDraggingDestination for file drops |
| `GlobalDragMonitor.swift` | Monitors system-wide drag events via `NSEvent.addGlobalMonitorForEvents` |
| `FileShelfManager.swift` | Manages temp file storage: copy/hard-link, expiry, capacity enforcement |
| `FileShelfView.swift` | SwiftUI view: horizontal scrolling shelf with file thumbnails |
| `FileThumbnailView.swift` | Async thumbnail generation via QuickLook + fallback system icons |
| `NotchGeometry.swift` | Computes notch rect and activation zone from screen geometry |
| `ScreenDetector.swift` | Detects notch/non-notch screens, observes display changes |
| `StatusBarController.swift` | Menu bar icon with file count badge and context menu |
| `SettingsManager.swift` | UserDefaults-backed settings with `@AppStorage` |
| `SettingsView.swift` | SwiftUI preferences UI |
| `SettingsWindowController.swift` | Manages the settings window lifecycle |
| `KeyboardShortcutManager.swift` | Global hotkey registration via Carbon Events API |

### State Machine

The panel has 5 states (defined in `DropZonePanel.swift`):

```
.hidden → .listening → .expanded → .collapsed → .hidden
                                 → .shelfExpanded → .collapsed
```

- **hidden**: No interaction, panel invisible
- **listening**: System drag detected, tracking cursor position
- **expanded**: Drop zone visible, accepting file drops
- **collapsed**: Collapsing animation in progress
- **shelfExpanded**: Shelf visible with file thumbnails (hover or hotkey triggered)

### File Storage

Temporary files are stored in `~/Library/Caches/com.dropzone.app/shelf/{UUID}/{filename}`.

- Same-volume files use hard-links to avoid doubling disk usage
- Cross-volume files are copied
- Files auto-expire (default 1 hour, configurable)
- Max capacity: 50 items / 2 GB (configurable)

### Concurrency Model

- Swift 6 strict concurrency mode is enabled
- UI-bound code uses `@MainActor`
- `@preconcurrency import AppKit` is used in `ScreenDetector.swift` as a pragmatic workaround for AppKit's incomplete Sendable annotations
- Callbacks from system APIs (NSEvent monitors, timers, Carbon handlers) must dispatch to `@MainActor` correctly — prefer `Task { @MainActor in }` over `MainActor.assumeIsolated` unless the API guarantees main-thread delivery

---

## Code Conventions

### Swift Style

- One primary type per file
- `@MainActor` annotation on classes that manage UI state
- Use Swift Testing (`@Test`, `#expect`) for unit tests, not XCTest
- Prefer SwiftUI for views, AppKit for system-level integration (panels, drag-and-drop, event monitoring)

### Testing

- Tests live in `DropZone/Tests/DropZoneTests/`
- Each source file has a corresponding test file
- Run with `cd DropZone && swift test`
- Ensure `DEVELOPER_DIR` points to Xcode, not Command Line Tools

### Build Commands

```bash
cd DropZone

# Debug build
swift build

# Release build
swift build -c release

# Run tests
swift test
```
