# Addendum — Replace Global Mouse Monitor with Transparent Hover-Detection Panel

- **Date:** 2026-04-17
- **Supersedes:** The `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` and `.leftMouseDragged` paths in `GlobalDragMonitor` for triggering pre-activation and drop-zone expansion. Also supersedes the previous addendum `2026-04-17-drag-preactivation-addendum-hover-trigger.md` — the approach is different.
- **Keeps intact:** `.preActivated` panel state, pre-activation bar UI stub, 380×60 size constant, shelf list redesign, settings.

## Context

Both the drag-triggered (`.leftMouseDragged`) and hover-triggered (`.mouseMoved`) paths through `NSEvent.addGlobalMonitorForEvents` fail to produce user-visible UI on the test machine **even when "Input Monitoring" is granted**. The existing drop-zone behaviour also never worked — the v0.3.0 and earlier releases users reported "drop zone appears" was actually the *panel's own* `NSDraggingDestination` (the drop zone is a window the user drags *into*, which fires `draggingEntered:` without needing any global event monitor). The `GlobalDragMonitor` pre-activation / expansion code has been non-functional end-to-end.

Meanwhile the reference implementation — [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) — never uses global event monitors for this flow. Its `NotchWindowController` creates a **full-width 200-pt-tall borderless window** pinned to the top of the notch screen. The window's content view uses standard AppKit `NSTrackingArea` `.mouseEntered` / `.mouseExited` to detect hover. No TCC permission involved — the app is reacting to events delivered to its own window, which is the normal AppKit path.

## Decision

Adopt the same architecture. Introduce a **hover-detection panel**:

- A borderless, transparent, click-through `NSPanel` always ordered-in at notch top, width = `preActivatedRect.width` (~276–396 px depending on hysteresis), height = `preActivatedRect.height` (~110 px).
- The panel is **invisible** (clear background, no content) but its content view has an `NSTrackingArea` with `.mouseEnteredAndExited + .activeAlways + .inVisibleRect` options.
- `mouseEntered(_:)` → call `DropZonePanel.enterPreActivation(...)` on the matching display's existing `DropZonePanel`.
- `mouseExited(_:)` → `DropZonePanel.exitPreActivation()`.
- Clicks pass through (`ignoresMouseEvents` toggled based on whether the drop UI needs to accept drops — see below).

Multi-display support uses the existing `panels: [CGDirectDisplayID: DropZonePanel]` pattern — we'll have `hoverPanels: [CGDirectDisplayID: HoverDetectionPanel]` per screen.

### Drop-zone expansion

For `.expanded` (drop zone), `DropZonePanel` is **already** an `NSDraggingDestination`. When the drag enters the already-expanded DropZonePanel window (or its hover panel during drag), standard `draggingEntered:` fires. So Step-2 of the state machine (pre-activated → expanded) happens when the drag actually enters the panel — no custom drag monitor needed.

### Drag-pasteboard read

The drag pasteboard *is* readable from within `NSDraggingDestination` callbacks (unlike the global sniff we were doing). That's where we can get `fileNames` for the pre-activation bar's content too.

## Implementation plan (bite-sized, rough)

1. New file `HoverDetectionPanel.swift` (`DropZoneLib`): borderless, transparent NSPanel, frame = `preActivationRect` in screen coords; subclass with `@MainActor` tracking-area lifecycle.
2. `HoverDetectionPanel` holds weak ref to its owner delegate (protocol) with two callbacks: `hoverEntered()` / `hoverExited()`.
3. In `AppDelegate.applicationDidFinishLaunching` (and on screen changes), create one `HoverDetectionPanel` per configured display. Delegate points at the matching `DropZonePanel`'s `enterPreActivation` / `exitPreActivation`.
4. When DropZonePanel enters `.expanded`, hide its hover panel's tracking (to avoid re-fire while the real panel is showing). When it returns to `.listening`/`.hidden`, re-show the hover panel.
5. Remove `GlobalDragMonitor` `.mouseMoved` registration added earlier (obsolete). Keep `.leftMouseDragged` / `.leftMouseUp` — they're still useful for tracking drag-session start/end independent of hit-testing.
6. Remove the `pasteboardHasFiles()` gate inside `handleDragMovement` — no longer relied on for the hover path.
7. Wire `DragDestinationView` (already exists) to read pasteboard filenames in `draggingEntered:` and hand them back to the pre-activation bar.
8. Bundle ID: keep `com.dropzone.app` for continuity; adhoc signing acceptable.

## Out of scope

- True "pre-activation shows filename" when the user hasn't yet entered the drop-zone panel — requires the hover panel to also register `NSDraggingDestination` to peek pasteboard during drag-hover. Nice-to-have; not blocking first usable cut.

## Exit criteria

Rebuild and launch. Without touching System Settings:
1. Mouse moves near notch → 380×60 pre-activation bar fades in.
2. Mouse moves away → bar fades out.
3. Drag a file into the notch panel → drop zone expands; on drop, file lands on shelf; shelf expands.
4. None of this requires granting Input Monitoring.
