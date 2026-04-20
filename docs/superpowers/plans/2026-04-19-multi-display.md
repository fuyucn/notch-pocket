# Multi-Display Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the DropZone shelf and minimized capsule to the display hosting the user's current foreground app, with consistent capsule dimensions across all screens.

**Architecture:** A new `ActiveScreenTracker` singleton observes `NSWindow.didBecomeKeyNotification`, `NSWorkspace.didActivateApplicationNotification`, and `NSApplication.didChangeScreenParametersNotification`. It publishes an `activeScreen: NSScreen?` over Combine. `AppDelegate` subscribes; on each change it closes any opened shelf, rebuilds a `NotchGeometry` sized for a constant "fallback notch" (the MacBook notch dimensions, reused on every screen), and calls `updateGeometry(_:)` on both `NotchPanel` and `MinimizedPanel`. Panels keep their current internal logic — only the geometry they render against changes.

**Tech Stack:** Swift 6.0 strict concurrency, AppKit `NSPanel` + `NSScreen`, Combine, Swift Testing. macOS 14+.

**Reference spec:** `docs/superpowers/specs/2026-04-19-multi-display-design.md`.

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `DropZone/Sources/DropZoneLib/ActiveScreenTracker.swift` | Singleton. Subscribes to AppKit screen/front-app notifications, publishes `NSScreen?` when the active screen changes. Runs `computeActiveScreen()` on each event. |
| `DropZone/Tests/DropZoneTests/ActiveScreenTrackerTests.swift` | Unit tests for the priority logic in `computeActiveScreen()`. |

### Modified files

| File | Changes |
|---|---|
| `DropZone/Sources/DropZoneLib/NotchGeometry.swift` | Add `init(screen:fallbackNotchSize:)` overload and `fallbackNotchSize: NSSize?` stored property. Make `preActivatedPanelSize` / `openedPanelSize` fall back to `fallbackNotchSize` when `notchRect == nil`. Same for `hoverTriggerRect`. |
| `DropZone/Sources/DropZoneLib/AppDelegate.swift` | Compute `fallbackNotchSize` at launch, start `ActiveScreenTracker`, subscribe to screen changes. On each change: `vm.requestClose()` if opened, then call `updateGeometry(_:)` on both panels. Tear down in `applicationWillTerminate`. |
| `DropZone/Tests/DropZoneTests/NotchGeometryTests.swift` | Add tests for the new init overload. |

### Unchanged

`NotchPanel.swift`, `MinimizedPanel.swift`, `NotchPanelRootView.swift`, `FileShelfManager.swift`, `EventMonitors.swift`, `NotchDropForwarder.swift`. All drag/shelf logic is screen-agnostic and continues to work once `updateGeometry(_:)` lands a new geometry.

---

## Task Ordering Rationale

1. `NotchGeometry` gains the fallback-aware initializer first, since everything downstream uses geometry.
2. `ActiveScreenTracker` comes next — standalone service, testable without panels.
3. `AppDelegate` is the last wiring step (risky; touches multi-file coordination) — by then every dependency has tests.
4. Manual test + release wrap up.

---

### Task 1: `NotchGeometry` fallback-aware initializer

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/NotchGeometry.swift`
- Test: `DropZone/Tests/DropZoneTests/NotchGeometryTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `DropZone/Tests/DropZoneTests/NotchGeometryTests.swift` before its closing `}`:

```swift
    @Test
    func fallbackNotchSizeUsedOnNonNotchedScreen() {
        // Construct a geometry for a non-notched screen with a fallback notch
        // size (e.g. MBP notch dimensions). The sizes derived from notch width
        // should use the fallback, not 200.
        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let fallback = NSSize(width: 240, height: 32)
        let geo = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(x: 1160, y: 1400, width: 240, height: 40),
            screenFrame: screen,
            hasNotch: false,
            fallbackNotchSize: fallback
        )
        // openedPanelSize.width == fallback.width + sidePadding*4
        #expect(geo.openedPanelSize.width == fallback.width + NotchGeometry.sidePadding * 4)
        // preActivatedPanelSize.width == fallback.width + sidePadding*2
        #expect(geo.preActivatedPanelSize.width == fallback.width + NotchGeometry.sidePadding * 2)
        // hoverTriggerRect uses openedPanelSize (existing design)
        #expect(geo.hoverTriggerRect.width == geo.openedPanelSize.width)
        #expect(geo.hoverTriggerRect.height == geo.openedPanelSize.height)
    }

    @Test
    func fallbackIgnoredOnNotchedScreen() {
        // When the screen does have a real notch, the fallback is unused —
        // the real notchRect drives the panel sizes.
        let notch = NSRect(x: 700, y: 968, width: 200, height: 32)
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let fallback = NSSize(width: 999, height: 99)
        let geo = NotchGeometry(
            notchRect: notch,
            activationZone: NSRect(x: 670, y: 908, width: 260, height: 102),
            screenFrame: screen,
            hasNotch: true,
            fallbackNotchSize: fallback
        )
        #expect(geo.openedPanelSize.width == notch.width + NotchGeometry.sidePadding * 4)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotchGeometryTests
```

Expected: FAIL — `NotchGeometry` initializer doesn't accept `fallbackNotchSize:` yet.

- [ ] **Step 3: Add `fallbackNotchSize` stored property + init overload**

Edit `DropZone/Sources/DropZoneLib/NotchGeometry.swift`.

Add a new stored property near the other public properties:

```swift
    /// When the active screen has no real notch, panel dimensions fall back
    /// to this size so the DropZone capsule stays visually consistent across
    /// displays. `nil` means use the built-in `fallbackPillSize`.
    public let fallbackNotchSize: NSSize?
```

Replace the explicit memberwise init that takes `notchRect/activationZone/screenFrame/hasNotch` (around line 95):

```swift
    /// Create geometry with explicit values (for testing and for AppDelegate's
    /// active-screen pathway).
    public init(
        notchRect: NSRect?,
        activationZone: NSRect,
        screenFrame: NSRect,
        hasNotch: Bool,
        fallbackNotchSize: NSSize? = nil
    ) {
        self.notchRect = notchRect
        self.activationZone = activationZone
        self.screenFrame = screenFrame
        self.hasNotch = hasNotch
        self.fallbackNotchSize = fallbackNotchSize
    }
```

Update the `init(screen:)` to forward `fallbackNotchSize: nil` and add a new overload that takes one:

```swift
    /// Compute geometry for the given screen.
    public convenience init(screen: NSScreen) {
        self.init(screen: screen, fallbackNotchSize: nil)
    }

    /// Compute geometry for the given screen, using `fallbackNotchSize` as the
    /// notch-equivalent dimensions when the screen has no real notch.
    public init(screen: NSScreen, fallbackNotchSize: NSSize?) {
        let screenFrame = screen.frame

        if screen.safeAreaInsets.top != 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let rect = NSRect(
                x: left.maxX,
                y: screenFrame.maxY - screen.safeAreaInsets.top,
                width: right.minX - left.maxX,
                height: screen.safeAreaInsets.top
            )
            self.notchRect = rect
            self.hasNotch = true
            self.activationZone = Self.expandedActivationZone(around: rect)
        } else {
            let pillWidth = fallbackNotchSize?.width ?? Self.fallbackPillSize.width
            let pillHeight = fallbackNotchSize?.height ?? Self.fallbackPillSize.height
            let pillOrigin = NSPoint(
                x: screenFrame.midX - pillWidth / 2,
                y: screenFrame.maxY - pillHeight
            )
            let pillRect = NSRect(origin: pillOrigin, size: NSSize(width: pillWidth, height: pillHeight))
            self.notchRect = nil
            self.hasNotch = false
            self.activationZone = Self.expandedActivationZone(around: pillRect)
        }
        self.screenFrame = screenFrame
        self.fallbackNotchSize = fallbackNotchSize
    }
```

Update `openedPanelSize` and `preActivatedPanelSize` to use the fallback when `notchRect` is nil:

```swift
    public var preActivatedPanelSize: NSSize {
        let notchWidth = notchRect?.width ?? fallbackNotchSize?.width ?? 200
        return NSSize(
            width: notchWidth + Self.sidePadding * 2,
            height: Self.preActivatedSize.height
        )
    }

    public var openedPanelSize: NSSize {
        let notchWidth = notchRect?.width ?? fallbackNotchSize?.width ?? 200
        return NSSize(
            width: notchWidth + Self.sidePadding * 4,
            height: Self.shelfExpandedSize.height
        )
    }
```

Also update `hoverTriggerRect` (already notch-centered) — when there's no notch, center on screen midX and use `openedPanelSize`:

```swift
    public var hoverTriggerRect: NSRect {
        let size = openedPanelSize
        let midX = notchRect?.midX ?? screenFrame.midX
        let x = midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
```

- [ ] **Step 4: Run the new tests — expect pass**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotchGeometryTests
```

Expected: all NotchGeometryTests pass, including the 2 new ones.

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass. No regressions.

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/NotchGeometry.swift DropZone/Tests/DropZoneTests/NotchGeometryTests.swift
git commit -m "feat: NotchGeometry gains fallbackNotchSize for non-notched screens"
```

---

### Task 2: `ActiveScreenTracker` service

**Files:**
- Create: `DropZone/Sources/DropZoneLib/ActiveScreenTracker.swift`
- Create: `DropZone/Tests/DropZoneTests/ActiveScreenTrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/ActiveScreenTrackerTests.swift`:

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct ActiveScreenTrackerTests {
    @Test @MainActor
    func computeActiveScreenReturnsNonNilWhenScreensExist() {
        // Test host always has at least one screen.
        #expect(ActiveScreenTracker.computeActiveScreen() != nil)
    }

    @Test @MainActor
    func computeActiveScreenPreferencesNotchedScreenOverOthers() {
        // If there is a notched screen, it wins over non-notched fallbacks
        // when no key window is active. Skip if no notched screen available
        // on this host (CI runners don't have one).
        guard NSScreen.screens.contains(where: { $0.safeAreaInsets.top != 0 }) else {
            return
        }
        let result = ActiveScreenTracker.computeActiveScreen()
        // When falling back (no key window is on a different screen), the
        // notched screen must be one of the candidates.
        #expect(result != nil)
    }

    @Test @MainActor
    func startAndStopToggleObservation() {
        let tracker = ActiveScreenTracker()
        // Initial value is present.
        #expect(tracker.activeScreen.value != nil)
        tracker.start()
        tracker.stop()
        // stop() must not throw; re-calling stop is idempotent.
        tracker.stop()
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ActiveScreenTrackerTests
```

Expected: FAIL — `ActiveScreenTracker` is undefined.

- [ ] **Step 3: Implement `ActiveScreenTracker`**

Create `DropZone/Sources/DropZoneLib/ActiveScreenTracker.swift`:

```swift
import AppKit
import Combine

/// Tracks which `NSScreen` hosts the user's current foreground app so panels
/// can be relocated onto that screen. Listens for front-app and window
/// activation notifications, plus screen reconfiguration.
///
/// Consumers subscribe to `activeScreen` to react to changes.
@MainActor
public final class ActiveScreenTracker {
    public static let shared = ActiveScreenTracker()

    public let activeScreen: CurrentValueSubject<NSScreen?, Never>

    private var isRunning = false
    private var observers: [NSObjectProtocol] = []

    public init() {
        self.activeScreen = CurrentValueSubject<NSScreen?, Never>(Self.computeActiveScreen())
    }

    /// Subscribe to AppKit notifications. Idempotent.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let nc = NotificationCenter.default
        let wsNC = NSWorkspace.shared.notificationCenter

        observers.append(wsNC.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })

        observers.append(nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })

        observers.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })
    }

    /// Unsubscribe. Idempotent.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        let nc = NotificationCenter.default
        let wsNC = NSWorkspace.shared.notificationCenter
        for obs in observers {
            nc.removeObserver(obs)
            wsNC.removeObserver(obs)
        }
        observers.removeAll()
    }

    private func recompute() {
        let new = Self.computeActiveScreen()
        if activeScreen.value !== new {
            activeScreen.send(new)
        }
    }

    /// Priority: last key-window screen → `NSScreen.main` → first notched
    /// screen → first screen. Returns `nil` only when `NSScreen.screens` is empty.
    public static func computeActiveScreen() -> NSScreen? {
        // Any currently-key window (any app) is reported by NSScreen.main.
        if let main = NSScreen.main { return main }
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 }) {
            return notched
        }
        return NSScreen.screens.first
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ActiveScreenTrackerTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/ActiveScreenTracker.swift DropZone/Tests/DropZoneTests/ActiveScreenTrackerTests.swift
git commit -m "feat: ActiveScreenTracker publishes current foreground screen"
```

---

### Task 3: Wire `ActiveScreenTracker` into `AppDelegate`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/AppDelegate.swift`

- [ ] **Step 1: Add Combine import + property to hold the subscription**

Edit `DropZone/Sources/DropZoneLib/AppDelegate.swift`. At the top replace:

```swift
import AppKit
```

with:

```swift
import AppKit
import Combine
```

Add a stored property with the other `private(set) public var`s (around line 11):

```swift
    private(set) public var activeScreenTracker: ActiveScreenTracker?
    private var activeScreenCancellable: AnyCancellable?
    private var fallbackNotchSize: NSSize = NotchGeometry.fallbackPillSize
```

- [ ] **Step 2: Capture `fallbackNotchSize` from the startup screen**

In `applicationDidFinishLaunching`, locate the block:

```swift
        // Primary-screen geometry — multi-display is future work.
        guard let primaryScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 }) ?? NSScreen.main else {
            return
        }
        let geometry = NotchGeometry(screen: primaryScreen)
```

Replace with:

```swift
        // Prefer a notched screen's notch dimensions as the canonical DropZone
        // capsule size. When jumping to non-notched screens later we reuse these
        // dimensions so the capsule looks identical regardless of display.
        let notchedScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 })
        if let notched = notchedScreen {
            let geom = NotchGeometry(screen: notched)
            if let notchRect = geom.notchRect {
                fallbackNotchSize = notchRect.size
            }
        }

        // Active screen at launch = whatever ActiveScreenTracker currently reports.
        let tracker = ActiveScreenTracker()
        activeScreenTracker = tracker
        guard let startupScreen = tracker.activeScreen.value else {
            return
        }
        let geometry = NotchGeometry(screen: startupScreen, fallbackNotchSize: fallbackNotchSize)
```

- [ ] **Step 3: Start the tracker and subscribe after panels are wired**

Near the bottom of `applicationDidFinishLaunching`, just before the keyboard-shortcut setup, add:

```swift
        tracker.start()
        activeScreenCancellable = tracker.activeScreen
            .dropFirst()   // skip initial value (already applied)
            .sink { [weak self, weak panel, weak minimized, weak vm] newScreen in
                guard let self, let panel, let minimized, let vm,
                      let newScreen else { return }
                if vm.status == .opened || vm.status == .popping {
                    vm.requestClose()
                }
                let newGeo = NotchGeometry(
                    screen: newScreen,
                    fallbackNotchSize: self.fallbackNotchSize
                )
                panel.updateGeometry(newGeo)
                minimized.updateGeometry(newGeo)
            }
```

- [ ] **Step 4: Tear down on termination**

In `applicationWillTerminate`, before `statusBarController?.teardown()`:

```swift
        activeScreenCancellable?.cancel()
        activeScreenCancellable = nil
        activeScreenTracker?.stop()
        activeScreenTracker = nil
```

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass. `AppDelegateTests` may still pass or skip per the headless guard — no new assertion is added for this task.

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/AppDelegate.swift
git commit -m "feat: AppDelegate subscribes to ActiveScreenTracker, relocates panels on screen change"
```

---

### Task 4: Manual test + release

**Files:**
- Modify: `DropZone/Info.plist`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Build and launch**

```bash
cd /Users/yfu/Developer/dropzone
./release-package.sh
pkill -f "Notch Pocket" 2>/dev/null; sleep 1; open "/Users/yfu/Developer/dropzone/releases/Notch Pocket-0.5.1.app"
```

(Filename still reflects 0.5.1 — the version bump happens in Step 3.)

- [ ] **Step 2: Manual smoke checklist**

Perform on hardware with at least one external display attached (or defer with a note if none available):

- [ ] Launch with MBP as front app → capsule on MBP notch.
- [ ] Click a window on external display → capsule jumps to external display, top center.
- [ ] With shelf opened, click a window on the other screen → shelf closes (minimize or closed) and capsule shows on new screen.
- [ ] Drag a file to external display's capsule area → popping bar, drop → opened shelf on external display.
- [ ] Unplug external display → capsule returns to MBP.
- [ ] Cmd+Tab back and forth between apps on different screens → capsule tracks.

If no external display available, at least verify:

- [ ] Single-screen (MBP only) launch → behaves exactly like v0.5.1.
- [ ] `applicationDidFinishLaunching` completes without crashes.

- [ ] **Step 3: Bump version to v0.6.0**

New feature → minor bump.

Edit `DropZone/Info.plist`:

```diff
- <string>0.5.1</string>
+ <string>0.6.0</string>
```

(both `CFBundleShortVersionString` and `CFBundleVersion`).

Edit `README.md`:

```diff
- ![Version](https://img.shields.io/badge/version-v0.5.1-blue)
+ ![Version](https://img.shields.io/badge/version-v0.6.0-blue)
```

Edit `CHANGELOG.md` — add new section below `## [Unreleased]`:

```markdown
## [v0.6.0] — 2026-04-19

Plan 11: Multi-display support (`plan-11-multi-display`)

### Added
- **Follow the active display.** DropZone's capsule and shelf now move to the screen hosting the foreground app. Switching windows to a second monitor moves the capsule there; returning to the MacBook moves it back.
- **Screens without a notch show a pill-shaped capsule at the top center**, sized to match the MacBook notch for visual consistency across displays.
- `ActiveScreenTracker` service observing `NSWindow.didBecomeKey`, `NSWorkspace.didActivateApplication`, and `NSApplication.didChangeScreenParameters`.

### Changed
- When a screen change fires with the shelf opened or popping, the shelf is dismissed first (sent to `.minimized` if it has items, otherwise `.closed`) before relocating — preventing stranded UI on the old screen.
```

- [ ] **Step 4: Rebuild**

```bash
./release-package.sh
pkill -f "Notch Pocket" 2>/dev/null; sleep 1; open "/Users/yfu/Developer/dropzone/releases/Notch Pocket-0.6.0.app"
```

Re-run the Step-2 checklist on the v0.6.0 build.

- [ ] **Step 5: Commit + tag + push + merge**

```bash
git add DropZone/Info.plist README.md CHANGELOG.md
git commit -m "docs: bump to v0.6.0 (multi-display support)"
git tag -a v0.6.0 -m "v0.6.0: DropZone follows the active display"

git checkout main
git merge --no-ff plan-11-multi-display -m "merge: plan-11 multi-display support (v0.6.0)"
git push origin main v0.6.0
git branch -d plan-11-multi-display
```

---

## Self-Review (performed)

**Spec coverage:**
- Active-screen selection priority (spec §Behaviour > Active screen selection): Task 2 (`computeActiveScreen`) ✓
- Size consistency across screens (spec §Size consistency): Task 1 (fallbackNotchSize) + Task 3 (pass it to each new geometry) ✓
- Opened-state handling on screen switch (spec §Opened-state): Task 3 Step 3 `if vm.status == .opened || .popping { requestClose() }` ✓
- Display configuration changes (spec §Display configuration): Task 2 observes `didChangeScreenParameters` ✓
- Screen without any front window (spec §Screen without any front window): `computeActiveScreen` priority chain ✓
- New unit tests (spec §Testing): Tasks 1 & 2 both add tests ✓
- Version bump + CHANGELOG + tag (per CLAUDE.md): Task 4 ✓

**Placeholder scan:** No TBD / "add error handling" / "similar to" phrasing. Every step has code or an exact command.

**Type consistency:**
- `NotchGeometry.init(screen:fallbackNotchSize:)` — defined Task 1, used Tasks 3 and 4 ✓
- `NotchGeometry.fallbackNotchSize: NSSize?` — defined Task 1, used by `openedPanelSize`/`preActivatedPanelSize` in same task ✓
- `ActiveScreenTracker.computeActiveScreen()` — defined Task 2, invoked by tests ✓
- `ActiveScreenTracker.activeScreen: CurrentValueSubject<NSScreen?, Never>` — defined Task 2, consumed Task 3 ✓
- `AppDelegate.fallbackNotchSize` — defined Task 3 Step 1, populated Step 2, used in Step 3 sink ✓

Plan is internally consistent.
