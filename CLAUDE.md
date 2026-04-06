> **Note:** This is an AI-generated side project — built collaboratively with AI assistance.

# Notch Pocket — Project Guidelines

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

**After merging to `main`** (mandatory — see [Post-Merge Release Checklist](#post-merge-release-checklist-mandatory)):

- [ ] `CHANGELOG.md` updated with new version entry (SemVer per [Version Tagging](#version-tagging))
- [ ] README version badge updated to match
- [ ] Annotated tag on `main` (`git tag -a vX.X.X -m "..."`) and **`git push origin vX.X.X`** to publish via CI

### Commit Message Convention

```
type: short description

Optional longer description.
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `build`

### Version Tagging

Follow **[Semantic Versioning](https://semver.org/)** — `major.minor.patch` (`vMAJOR.MINOR.PATCH`). **Whenever shippable code changes land on `main`**, the next release must use a tag that reflects the **kind of change** in that release (not arbitrary numbers).

| Bump | When to increase | Examples |
|------|-------------------|----------|
| **MAJOR** | Breaking or incompatible changes for users | Removed menu actions, changed hotkey defaults requiring migration, shelf path/format incompatible with prior versions |
| **MINOR** | New features or user-visible behavior, **backward compatible** | New setting, new shelf behavior, notch UI tweak that does not break existing flows |
| **PATCH** | Bug fixes, small corrections, **no new user-facing contract** | Crashes fixed, wrong geometry corrected, internal refactor with same behavior |

- If a single release mixes changes, bump to the **highest** level required (e.g. one breaking change ⇒ major).
- **Pre-1.0** (`0.y.z`): treat **minor** as meaningful feature lines and **patch** as fixes; reserve **major** (`1.0.0`) for the first stable/API-stable milestone if you adopt that convention.

Tag format: `v0.1.0`, `v0.2.0`, `v1.0.0`

Tags are only created on **`main`**, after the relevant work is merged. **CI does not choose or create version numbers** — you assign **SemVer** when you tag.

#### Automated release (GitHub Actions)

Pushing an **annotated tag** matching `v*` triggers `.github/workflows/release.yml`:

1. Verifies the tag points to a commit on **`main`** (not a feature-only branch).
2. Builds a **universal** (arm64 + x86_64) `Notch Pocket.app` and uploads **`Notch-Pocket-<version>.zip`** to **GitHub Releases**.

So: **versioning is manual and SemVer-driven**; **packaging and publishing the binary** is automatic once the tag is pushed.

```bash
git push origin v0.X.0
```

Local packaging without CI: `./release-package.sh` from the repo root (see `DropZone/Info.plist` / `VERSION_OVERRIDE`).

#### Post-Merge Release Checklist (mandatory)

After every merge to `main` that should produce a release, complete the following before moving on:

1. **Update `CHANGELOG.md`** — Add a new version entry at the top with:
   - Version number and date (`## [v0.X.0] — YYYY-MM-DD`)
   - Summary of changes grouped by type (Added, Changed, Fixed)
   - Reference to the plan/branch that was merged
2. **Update `README.md` version badge** — Match the new release version.
3. **Create annotated git tag on `main`** (SemVer from the table above):
   ```bash
   git tag -a v0.X.0 -m "vX.X.X: short description of release"
   ```
4. **Push the tag** — Triggers the Release workflow and publishes the zip:
   ```bash
   git push origin v0.X.0
   ```

Keep **`DropZone/Info.plist`** version fields (`CFBundleShortVersionString`, `CFBundleVersion`) aligned with the release: locally update before tagging, or rely on CI (`VERSION_OVERRIDE` from the tag in `release-package.sh`) so the shipped `.app` matches the tag.

A release-worthy merge is not complete until `CHANGELOG`, README, tag, and tag push are done (and the workflow succeeds).

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
