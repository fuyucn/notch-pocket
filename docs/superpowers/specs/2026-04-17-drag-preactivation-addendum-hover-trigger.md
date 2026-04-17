# Addendum — Hover-Triggered Pre-Activation Bar

- **Date:** 2026-04-17
- **Supersedes:** Pre-activation trigger logic in `2026-04-17-drag-preactivation-and-shelf-redesign-design.md` §§2–3
- **Leaves intact:** Pre-activation bar UI, `.preActivated` state, 380×60 size, list view redesign, settings.

## Context

During manual testing of the initial implementation, we observed that `GlobalDragMonitor`'s pasteboard-based gate (`pasteboardHasFiles()` on `NSPasteboard(name: .drag)`) does not reliably return `true` for drags originating outside the app. Even with "Input Monitoring" granted, `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged)` deliver events — but the drag pasteboard remains empty from our process's view, so `isDragActive` never flips and the downstream pre-activation / drop UI never surfaces.

Reference implementation — [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) — avoids this issue entirely by **not** trying to detect "is the user dragging a file right now?" from the global pasteboard. Instead it:

1. Monitors `.mouseMoved` globally.
2. Shows the notch UI whenever the cursor approaches the notch — drag or no drag.
3. Uses `NSDraggingDestination` on the notch window itself to handle dropped files when they arrive.

## Decision

Adopt the hover-based trigger:

- The **pre-activation bar shows whenever the cursor enters the `preActivationRect`**, regardless of whether a system drag is in progress.
- The bar leaves the screen when the cursor leaves the `activationZone` (hysteresis stays the same).
- Drag-specific content (filename preview, shelf badge) is a later enhancement; the addendum targets the **visibility behaviour** first.

## Implementation changes

1. **`GlobalDragMonitor`**:
   - Add a `.mouseMoved` global + local monitor that fires `onPreActivationEntered(displayID, fileNames)` / `onPreActivationExited(displayID)` based on cursor position relative to each screen's `preActivationRect` / `activationZone`.
   - No pasteboard read required for the entry decision.
   - Existing `.leftMouseDragged` / `.leftMouseUp` handling (drag session start/end tracking, polling) stays as-is — it still drives `onDragEnteredZone` / `onDragEnded` for the inner `.expanded` path.
   - `fileNames` passed to `onPreActivationEntered` is a best-effort read from `NSPasteboard(name: .drag)`; may be `[]` most of the time. The bar's UI degrades to "Dragging…" or a static icon when empty.

2. **`AppDelegate`** wiring: unchanged in shape. The `onPreActivationEntered` handler is already wired in commit `943fd7a`.

3. **Drag-drop correctness** preserved: `DragDestinationView` on the panel still handles actual `NSDraggingDestination` callbacks when a drag enters its window. That path was never broken.

## Out of scope

- Pasteboard-based filename display — punted. Until we find a reliable way to read the drag pasteboard (may require per-drop-target access, not global read), the bar shows a generic "Drop here" primary text when not actively dragging.
- Dragging detection for `.expanded` still uses `.leftMouseDragged` + `pasteboardHasFiles()` for now. Investigate whether hover-only is enough there as well.

## Exit criteria

Manual verification: mouse approaches notch (not dragging) → 380×60 bar appears; mouse leaves → bar fades out. The bar is visible on *any* hover, not only during drag.
