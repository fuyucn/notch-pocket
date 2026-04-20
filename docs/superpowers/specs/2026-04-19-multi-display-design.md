# Multi-Display Support — Design Spec

**Status:** Accepted
**Date:** 2026-04-19
**Branch:** `plan-11-multi-display` (off `main` at v0.5.1)
**Predecessor:** v0.5.1 — `AppDelegate` picks a single `NSScreen` at launch (the first notched screen or `NSScreen.main`) and wires it into one static `NotchGeometry`. No reaction to screen changes or front-app changes.

## Goal

The DropZone shelf and minimized capsule should appear on the display currently hosting the user's foreground app. When the user switches focus to a window on another display, both panels jump to that display. Shelf content (the list of stored files) is global — there is only one shelf regardless of which display it's rendered on.

## Why

Users with external monitors don't want to look up at the MacBook notch when their actual workflow is on a second screen. Forcing DropZone to always live on the notch makes the feature useless for common setups (laptop closed + external, multi-monitor coding).

## Scope

### In scope

- Track which screen hosts the foreground app's key window and relocate DropZone there.
- Support screens without a notch: show a pill-shaped DropZone at the top center of that screen, with the same dimensions as the MacBook notch DropZone.
- Recompute when displays are added, removed, or reconfigured.
- Preserve shelf contents across screen changes (shelf is a single shared state, not per-screen).
- Dismiss the opened shelf before jumping to a new screen (avoid half-shown UI on the wrong screen).

### Out of scope

- Persistent per-screen shelves.
- Animated transition between screens (plain orderOut/orderFront is fine).
- Following mouse pointer instead of front-app. (Per user decision: front-app only.)
- Custom per-screen sizing of the DropZone capsule. (Fixed to MacBook notch dimensions everywhere.)
- Supporting display-mirroring as a distinct mode. (Just picks one NSScreen using system defaults.)

## Behaviour

### Active screen selection

Priority-ordered:

1. `NSApp.keyWindow?.screen` — this app (if ever key), fallback that almost never applies since DropZone is an accessory app.
2. Front app's main/key window's `.screen`. Use `NSWorkspace.shared.frontmostApplication` → `runningApplication.ownsMenuBar` etc. — but the reliable path is to observe `NSWorkspace.didActivateApplicationNotification` + `NSWindow.didBecomeKeyNotification` and cache the last front-app's screen from the notification's window info.
3. **Fallback chain when no clear front window:**
   a. First screen whose `safeAreaInsets.top != 0` (notched MacBook display).
   b. `NSScreen.main`.
   c. `NSScreen.screens.first`.

### Size consistency across screens

The DropZone capsule dimensions are derived from the MacBook notch regardless of the currently active screen:

- A `fallbackNotchSize` is computed once at launch from the MacBook notched screen (if any) or from `NotchGeometry.fallbackPillSize` (`200 × 32`) if no notched display exists.
- `NotchGeometry` gains an optional initializer parameter `fallbackNotchSize: NSSize`. On a screen without a real notch, the geometry uses this value everywhere it would normally use `notchRect.width` / `notchRect.height` (for `openedPanelSize`, `preActivatedPanelSize`, centering math).
- `notchRect` remains `nil` on non-notched screens — the visual shape still uses a pill (rounded on all four corners) via existing `NotchShape.closedBottomRadius`-style code.

Result: the shelf always looks the same size and shape regardless of which screen it's on. Only the *screen* differs.

### Opened-state handling on screen switch

If `vm.status == .opened` when a screen change fires:

1. First call `vm.requestClose()` — sends to `.minimized` (if shelf has items) or `.closed`.
2. Then apply the new geometry.

Rationale: preserving the open shelf on a different screen mid-drag would leave the user clicking on the wrong screen. Closing first keeps the mental model simple.

`.popping` should not be observed during a screen change (user would only be in `.popping` during an active drag session — they are not also switching apps). If it happens, treat it like `.opened` and close first.

### Display configuration changes

`NSApplication.didChangeScreenParametersNotification` → re-run active screen selection. If the formerly-active screen is gone, the new active screen per priority rules wins.

### Screen without any front window (startup, all-hidden)

`computeActiveScreen()` falls through the priority chain. Default to notched screen → `NSScreen.main` → first screen.

## Architecture

### New file: `DropZone/Sources/DropZoneLib/ActiveScreenTracker.swift`

```swift
@MainActor
public final class ActiveScreenTracker {
    public static let shared = ActiveScreenTracker()

    /// Publishes whenever the computed active screen changes.
    public let activeScreen: CurrentValueSubject<NSScreen?, Never>

    private init() { ... }

    public func start() { ... }  // subscribe to workspace + window notifications
    public func stop()  { ... }  // unsubscribe

    /// Public for testing and ad-hoc recomputation.
    public static func computeActiveScreen() -> NSScreen? { ... }
}
```

- Observed notifications:
  - `NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, ...)`
  - `NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, ...)` (captures within-app window switches)
  - `NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, ...)`
- All notification handlers trampoline to `MainActor` and call `recompute()`, which computes the new active screen and, if different from the last published value, sends via `activeScreen.send(_:)`.

### Modified: `DropZone/Sources/DropZoneLib/NotchGeometry.swift`

Add an initializer overload:

```swift
public init(screen: NSScreen, fallbackNotchSize: NSSize) {
    self.screenFrame = screen.frame
    if screen.safeAreaInsets.top != 0, /* has real notch */ {
        // same as before
    } else {
        // Non-notched screen: `notchRect` stays nil, but use `fallbackNotchSize`
        // in all derived sizes so panels have consistent width across screens.
        self.notchRect = nil
        self.hasNotch = false
        self.fallbackNotchSize = fallbackNotchSize
        // activationZone based on a virtual pill at top center using fallbackNotchSize
    }
}
```

Add a stored property `fallbackNotchSize: NSSize?` (nil only in the legacy init for tests).

Update computed vars `preActivatedPanelSize`, `openedPanelSize`, etc., to fall back to `fallbackNotchSize ?? NSSize(width: 200, height: MinimizedBarView.height)` when `notchRect` is nil.

### Modified: `DropZone/Sources/DropZoneLib/AppDelegate.swift`

Inside `applicationDidFinishLaunching`, after initial `NotchGeometry` and panel creation:

1. Capture the MacBook notched screen (if any) to determine `fallbackNotchSize`.
2. Start `ActiveScreenTracker.shared`.
3. Subscribe to `ActiveScreenTracker.shared.activeScreen`:
   - Skip the initial value (we already initialized panels with it).
   - On each subsequent value: if `vm.status == .opened`, call `vm.requestClose()` first. Then build a new `NotchGeometry(screen: newScreen, fallbackNotchSize: fallbackNotchSize)`. Call `notchPanel.updateGeometry(_:)` and `minimizedPanel.updateGeometry(_:)`.

Inside `applicationWillTerminate`: `ActiveScreenTracker.shared.stop()`.

### Unchanged (!)

- `NotchPanel` internal layout.
- `MinimizedPanel` internal layout.
- `NotchPanelRootView` SwiftUI tree.
- `FileShelfManager` (shelf is global — no changes needed).
- `EventMonitors` / `NotchDropForwarder` (drag-in still works on the panel wherever it is).

Because the panels' `updateGeometry(_:)` methods already exist and already re-run `containerFrame(for:)` math, nothing new on their side.

## Testing

### New unit tests

1. `ActiveScreenTrackerTests`
   - `computeActiveScreen()` returns non-nil on any host with a screen.
   - When `NSApp.keyWindow` is nil and no front app, returns notched screen if available, otherwise `NSScreen.main`.
   - Running `start()` + swapping a stub front-window notification updates `activeScreen`.

2. `NotchGeometryTests` (extend)
   - `init(screen:fallbackNotchSize:)` on a non-notched screen produces `notchRect == nil` but `openedPanelSize.width == fallbackNotchSize.width + sidePadding*4`.
   - `init(screen:fallbackNotchSize:)` on a notched screen behaves the same as the existing initializer (the fallback is unused when the real notch is available).

3. `AppDelegateTests` (extend or just verify via manual test)
   - Skip under headless per existing guard.

### Manual tests (on hardware)

- Plug in external display → move Chrome to it → shelf capsule appears on external display.
- Switch focus back to MBP window → shelf capsule moves back.
- With shelf opened and files inside, switch focus to a different screen → shelf closes (minimized) and capsule appears on new screen.
- Unplug external display while active → capsule retreats to MBP.
- Display-mirror two screens → use either. (System collapses to one `NSScreen.main` per mirror set.)

## Risks

| Risk | Mitigation |
|---|---|
| Screen-change notifications fire mid-drag, panel jumps away from drag target | `requestClose()` first on status `.opened`. `.popping` during screen change is an edge case — treat like `.opened`. |
| `NSWindow.didBecomeKeyNotification` doesn't fire for Finder desktop clicks | Also listen for `NSWorkspace.didActivateApplicationNotification`, which fires when Finder activates. |
| `NSScreen.main` behaves differently when the lid is closed on Apple Silicon | If no notched screen exists, fallback to `NSScreen.main`. On Intel laptops with closed lid, `NSScreen.main` is the external — correct outcome. |
| Active screen computed during a dispatched notification sees stale `NSApp.keyWindow` | Recompute is idempotent; when state eventually settles, a later notification (window-did-become-key) re-fires and the cached value converges. |

## Out of scope reminders (don't let these creep in)

- Per-screen shelves
- Per-screen custom capsule sizing
- Smooth screen-change animations
- Display picker UI in settings
- Auto-switch by mouse position
