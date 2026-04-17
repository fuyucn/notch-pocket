# Addendum — NotchDrop-Style Architecture Rewrite (A-big)

- **Date:** 2026-04-17
- **Supersedes:** `HoverDetectionPanel` + `DropZonePanel` animation state machine + `GlobalDragMonitor` pre-activation path. Parts of `2026-04-17-hover-detection-panel.md` remain relevant (transparent-window approach) but the architecture is now consolidated.
- **Keeps intact:** `ShelfItem` fields (`sourceAppName`, `fileExtension`), `SettingsManager.shelfViewMode` / `shelfPersistence`, `PermissionsManager`, `FileShelfManager` semantics, settings UI scaffolding.

## Context

After extensive field testing, the current architecture (hidden `NSPanel` that `orderOut`s when idle and relies on `NSEvent.addGlobalMonitorForEvents` to show itself) proved unreliable:
- global event monitors silently fail without Input Monitoring permission, and every `adhoc` re-sign invalidates the TCC hash
- drag-based auto-show requires pasteboard sniffing which is unreliable cross-process
- the workaround `HoverDetectionPanel` ate clicks because `ignoresMouseEvents = false` was needed for `draggingEntered`, without compensating click-through

Reference implementation [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) uses a fundamentally different approach that does **not** have these problems:
- a **single, always-visible, full-width borderless NSWindow** covers the top 200pt of the notch screen
- inside it, SwiftUI draws different forms driven by a `NotchViewModel.Status` (`.closed` / `.popping` / `.opened`)
- the window is a native `NSDraggingDestination` for drops
- `EventMonitors` (global + local) publishes `mouseLocation` to the view model so hover-proximity drives status transitions — but `.mouseMoved` local monitor delivers events inside our own window **without any TCC permission**, which covers the entire triggering area we need (top 200pt of screen)

## Decision

Replace the DropZonePanel/HoverDetectionPanel pair with a single `NotchPanel` following NotchDrop's pattern. This is a large rewrite but the only path that delivers reliable hover + drag behaviour.

## Architecture

```
NotchPanel (always-visible NSWindow)
  = full screen width × 200pt tall, top-anchored below menu bar
  = borderless, transparent, .popUpMenu level
  = ignoresMouseEvents toggles: true when .closed (click-through), false when .popping/.opened
  = registered NSDraggingDestination for file drops
  └── contentView: NSHostingView<NotchPanelRootView>
        └── NotchPanelRootView (SwiftUI)
             switch on viewModel.status {
               .closed   → EmptyView (no hit-testing, no pixels)
               .popping  → PreActivationBarView (380×120, centered under notch)
               .opened   → ShelfContainerView (600×360, list/thumbnail toggle, header)
             }

NotchViewModel (@MainActor, ObservableObject)
  @Published status: Status        // .closed / .popping / .opened
  @Published primaryFileName: String?
  @Published extraCount: Int
  @Published shelfCount: Int
  @Published isDragging: Bool

  func open(reason:)     // status = .opened
  func pop(fileNames:)   // status = .popping
  func close()           // status = .closed

EventMonitors (replaces GlobalDragMonitor)
  shared = EventMonitors()
  mouseLocation: CurrentValueSubject<NSPoint, Never>
  isDragging: CurrentValueSubject<Bool, Never>
  (registers .mouseMoved + .leftMouseDragged + .leftMouseUp global+local via
   simple EventMonitor wrapper, same pattern as Lakr233/NotchDrop)

NotchViewModel observes EventMonitors.mouseLocation and transitions status:
  - pointer in "hover trigger rect" AND isDragging == true → .popping
  - pointer in "expanded drop rect" AND isDragging == true → .opened
  - pointer outside both AND not dragging → .closed
  (final rules tuneable; exact thresholds in implementation plan)
```

## Out of scope (for now)

- Non-drag hover triggering `.popping` — user explicitly said "不拖就不用显示预激条"; status stays `.closed` unless `isDragging`
- Multi-display support beyond the primary notched screen — the existing plan-5 external-display work will need to be re-applied after this rewrite
- Carbon keyboard shortcut path — unchanged
- `GlobalDragMonitor` legacy pasteboard-sniff drag detection — retired, replaced by `EventMonitors`

## Files affected

### New
- `NotchPanel.swift` — the always-visible NSWindow / NSPanel
- `NotchPanelRootView.swift` — SwiftUI switch-on-status root
- `NotchViewModel.swift` — status, file names, drag state
- `EventMonitors.swift` — singleton event bus (Combine)
- `EventMonitor.swift` — thin NSEvent global+local monitor wrapper

### Retired
- `DropZonePanel.swift` (all of it)
- `DropZonePanel`-state enum tests
- `HoverDetectionPanel.swift`
- `GlobalDragMonitor.swift`
- `ScreenDetector.swift` — supersede with simpler primary-screen observation inside AppDelegate

### Modified
- `AppDelegate.swift` — construct NotchPanel + NotchViewModel, tear down on termination
- `PreActivationBarView.swift` — still used, now hosted inside NotchPanelRootView at `.popping`
- `FileShelfView.swift` / new `ShelfContainerView.swift` — hosted at `.opened`
- `FileShelfManager.swift` — unchanged
- `SettingsManager.swift` — unchanged
- `SettingsView.swift` — unchanged (PermissionsManager section still useful)
- All tests that imported `DropZonePanel` / `HoverDetectionPanel` / `GlobalDragMonitor` — port to new types, drop ones obsoleted by the rewrite

## Exit criteria

1. Launch app (no TCC permission requested, no permission needed for basic function).
2. Drag a file from Finder toward the top of the screen. At some point crossing into the top 200pt region, the PreActivationBarView (380×120) appears below the notch.
3. Continue dragging into the notch. The view expands to 600×360 showing drop zone / shelf.
4. Drop the file. It lands on the shelf. Panel auto-hides per `shelfPersistence`.
5. Click anywhere in the top 200pt strip while **not** dragging or hovering: click passes through to the underlying app.
6. Menu bar icons near the notch remain clickable at all times.

## Implementation plan

A detailed bite-sized plan will be written as a follow-up to this spec (see `docs/superpowers/plans/`), because the rewrite is large (~400 LOC delta, ~10 files). Plan will use TDD for the view model + EventMonitors (the parts amenable to unit tests) and manual verification for the window/hit-test/visual parts.
