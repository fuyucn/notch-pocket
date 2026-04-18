# Minimized Notch Bar — Design Spec

**Status:** Accepted
**Date:** 2026-04-18
**Branch:** `plan-9-minimize-retry` (off v0.4.5)
**Predecessor:** `docs/superpowers/plans/2026-04-17-minimized-state.md` — prior attempt reverted; this spec supersedes.

## Goal

Give the shelf a permanent-but-unobtrusive indicator when it holds files — a Dynamic-Island-style black capsule that physically wraps around the MacBook notch, showing a tray logo on the left shoulder and the file count on the right shoulder. A single click anywhere on the capsule opens the full shelf.

The minimize state must NOT occlude the menu bar or any screen content. It exists only in the narrow band of pixels directly adjacent to the notch.

## Why (context)

1. Users forget files they've stashed when the shelf fully disappears on close. A permanent reminder solves this.
2. The opened shelf is one click away from minimize, so quick drag-out workflows no longer require the user to remember a hotkey or hunt for the menu-bar icon.
3. A previous attempt (`89a76d0` → reverted in `29f6e56`) added a `.minimized` state but coupled the change to a broader panel-frame / hit-test rewrite that regressed drag-in. This spec intentionally decouples: the minimize UI lives in a **separate NSPanel** so the existing `NotchPanel` state machine (`.closed / .popping / .opened`) is untouched.

## Behaviour

### Status enum

`NotchViewModel.Status` gains a fourth case: `.minimized`.

### State machine

```
.closed ──(shelf gains its first file)──────> .minimized
.minimized ──(user tap on the capsule)─────> .opened
.minimized ──(drag-in near notch)──────────> .popping (→ .opened on drop)
.opened ──(× / esc / click-outside)────────> requestClose()
.minimized ──(shelf emptied)───────────────> .closed
.popping ──(drag ended outside, shelf has items)──> .minimized
.popping ──(drag ended outside, shelf empty)──────> .closed
```

Where `requestClose()` = `shelfCount > 0 ? .minimized : .closed`.

### App launch

When `applicationDidFinishLaunching` finishes wiring the shelf manager, read `shelfManager.items.count`. If > 0, set the initial `vm.status = .minimized`. Otherwise `.closed`.

### Drag-in from minimize

Behaves identically to drag-in from `.closed` or `.popping`: the system drag enters the main `NotchPanel`'s drop forwarder (covers `hoverTriggerRect`), which sets `isDragInside=true` and transitions the status to `.popping`. No additional drag-detection code is needed for the minimize capsule itself — `NotchPanel` already covers the needed rect.

When `.popping` ends (drag exited without drop OR drop completed), the state machine above decides between `.minimized` and `.closed` based on shelfCount.

## Visual

A single black capsule:

```
◤─────────────────────────◥   ← top edge flush with screen top
│  📁  │   [notch]   │  5  │
◣─────────────────────────◢
   ▲         ▲         ▲
 left      physically   right
shoulder   hidden by   shoulder
           notch
```

- **Height**: equals `notchRect.height` (~32pt on a 14"/16" MBP). Top edge flush with screen top so the notch itself covers the middle vertically.
- **Width**: `notchRect.width + (2 × shoulderWidth)`, where `shoulderWidth ≈ 50pt`. Empirically tuned later; spec reserves freedom to adjust.
- **Corner radius**: outer corners only — the shape is a horizontal capsule. Inner corners (bordering the notch) can reuse `NotchShape.closedBottomRadius` or remain squared off since the notch physically hides them.
- **Fill**: solid black (`Color.black`), subtle white stroke at 15% opacity — matches existing `NotchShape` treatment.
- **Left shoulder content**: `Image(systemName: "tray.fill")`, size 11pt, white 90%.
- **Right shoulder content**: `Text("\(shelfCount)")`, 11pt semibold, white; wrapped in a soft translucent capsule background (`Color.white.opacity(0.18)`) if count display benefits from it — visual polish decision at implementation time.
- **Shadow**: light drop shadow to lift it off the wallpaper, matching NotchPanel.

## Interaction

- **Click anywhere on the capsule** → `vm.status = .opened`. (User cannot actually click the middle section because the notch physically covers it, but the gesture is applied to the whole capsule view for simplicity.)
- Everything outside the capsule's frame is untouched — the MinimizedPanel's window frame is exactly the capsule bounding box, so pointer events to any screen pixel outside that box go straight through to apps below.
- **No drag-out from minimize**: to drag files out of the shelf, user must first click to `.opened`.

## Architecture

### New files

1. `DropZone/Sources/DropZoneLib/MinimizedPanel.swift` — `NSPanel` subclass.
   - Frame = capsule bounding box, positioned so top edge aligns with screen top, horizontally centered on the notch.
   - Style: `[.nonactivatingPanel, .borderless]`, level `.popUpMenu`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
   - `isOpaque = false`, `backgroundColor = .clear` (so the rounded capsule edges look clean).
   - `hasShadow = false` (SwiftUI handles the shadow), `ignoresMouseEvents = false`.
   - Hosts a single SwiftUI `MinimizedBarView` via `NSHostingView`.
   - Observes `vm.status` via Combine: shows (`orderFront`) when status == `.minimized`, hides (`orderOut`) otherwise.
   - Observes `vm.geometry` changes (display reconfig) and re-computes frame.

2. `DropZone/Sources/DropZoneLib/MinimizedBarView.swift` — SwiftUI `View`.
   - Takes `shelfCount: Int`, `notchRect: NSRect?`, `onTap: () -> Void`.
   - Uses an `HStack` with explicit spacer (width = notchRect.width) in the middle to reserve the notch region.
   - Wraps the whole thing in a capsule shape with `onTapGesture { onTap() }`.

### Modified files

3. `DropZone/Sources/DropZoneLib/NotchViewModel.swift`
   - Add `.minimized` to `Status`.
   - Add `public func requestClose()` that returns `.minimized` or `.closed` based on `shelfCount`. (Note: `requestClose()` already exists in current source — verify and adapt.)
   - `updateMouseLocation` already handles `.closed → .popping → .opened` from mouse-drag events. `.minimized` should be treated like `.closed` as a "drag entry" state — easiest approach: in the `guard isDragging else { status = .closed }` arm, skip resetting if already `.minimized` (the transition back to `.minimized` happens via other paths).

4. `DropZone/Sources/DropZoneLib/AppDelegate.swift`
   - After creating the view model, if `shelfManager.items.count > 0` set `vm.status = .minimized`.
   - Instantiate `MinimizedPanel(viewModel: vm)` and retain it on AppDelegate (`private(set) var minimizedPanel: MinimizedPanel?`).
   - In the existing `shelfManager.onItemsChanged` callback: when `count` drops to 0 AND `vm.status == .minimized`, set `vm.status = .closed`. When count rises from 0 AND `vm.status == .closed` AND not in a drag, set `.minimized`.
   - `applicationWillTerminate`: `minimizedPanel?.orderOut(nil); minimizedPanel = nil`.

5. `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift`
   - Add `.minimized` case to the big `switch viewModel.status` blocks. For `targetSize` return `.zero`, for content return `Color.clear`. This keeps the existing NotchPanel invisible during minimize — the MinimizedPanel takes over the visible UI.

### Unchanged (important!)

- `NotchPanel.swift` — state machine for closed/popping/opened is untouched.
- `NotchDropForwarder.swift` — drop forwarder logic is untouched.
- `FileShelfManager.swift` — no changes.
- `EventMonitors.swift` — no changes (drag-in continues to work through the existing path).
- Frame / hit-test / ignoresMouseEvents of NotchPanel: untouched.

## Testing

New unit tests:

1. `NotchViewModelTests`:
   - Status transitions: `.closed` + shelf gains first file → `.minimized` (depends on app-level wiring, so maybe exercised in AppDelegate test instead)
   - `requestClose()` with `shelfCount > 0` → `.minimized`
   - `requestClose()` with `shelfCount == 0` → `.closed`
   - `updateMouseLocation(isDragging: true)` while `.minimized` + point in activationZone → `.opened`

2. `MinimizedBarViewTests` (smoke test):
   - View renders without crash at various count values (0, 1, 99).

3. `MinimizedPanelTests`:
   - Panel created with geometry has frame positioned at top of screen, centered on notch.
   - Panel's window level is `.popUpMenu`.
   - Panel orderFront when status becomes `.minimized`; orderOut when status changes to other states.
   - Panel's frame is sized to the capsule bounding box, NOT the full screen width.

## Out of scope

- **Persistence**: Shelf items restored from disk on launch will already drive `.minimized` via launch-time count check. Nothing extra needed.
- **Animations between states**: Initial implementation uses straight orderFront/orderOut (no fade/morph). Animation polish can be a follow-up.
- **Drag-out from the minimize capsule**: User must open first. Adding drag-out here would require items on the capsule itself, which breaks the "just a tray icon + count" simplicity.
- **Customizing the capsule width per user setting**: Hard-coded `shoulderWidth = 50` for now.
- **Multi-display**: Uses primary-notch-screen geometry, same as existing NotchPanel. Multi-display is future work.

## Risks and mitigations

| Risk | Mitigation |
|------|------|
| Regresses drag-in, like last time | MinimizedPanel is a separate window. NotchPanel and NotchDropForwarder untouched. Drag-in continues through `NotchPanel.dropForwarder`. |
| MinimizedPanel's small frame blocks clicks somewhere in the notch area that users need | Frame is smaller than `hoverTriggerRect`; its footprint is literally just the capsule pixels. Click elsewhere → NotchPanel's `hoverTriggerRect` rect is there and routes properly. |
| Two panels visible at once during state transition (flicker) | Add an invariant: minimized panel `orderOut` fires immediately when status leaves `.minimized`. Unit-tested. |
| User clicks shoulder but NotchPanel's overlapping hoverTriggerRect eats the click | MinimizedPanel's window level is `.popUpMenu` (same as NotchPanel) but ordered in *after* NotchPanel at panel-creation time → AppKit resolves overlapping same-level windows in front-to-back order. If this breaks, fallback is `level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)`. |

## Commit plan (to be refined in the plan document)

1. Add `.minimized` to `NotchViewModel.Status` + tests.
2. Add `MinimizedBarView.swift` + view tests.
3. Add `MinimizedPanel.swift` + panel tests.
4. Wire MinimizedPanel in `AppDelegate`; adjust shelf-count-changed callback.
5. Handle `.minimized` in NotchPanelRootView (render nothing).
6. Launch-time count check → `.minimized`.
7. Hand-test: drag-in from minimize, tap to open, close-back-to-minimize, menu bar click-through.
8. Version bump + changelog + release on tag.
