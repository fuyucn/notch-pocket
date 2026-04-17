# Drag Pre-Activation Bar & Shelf List Redesign — Design Spec

- **Date:** 2026-04-17
- **Branch:** `plan-5-external-display-and-duplicate-fix` (current) — a new feature branch `plan-6-preactivation-and-shelf-list` will be cut from `main` before implementation per CLAUDE.md.
- **Status:** Draft awaiting user review.

## 1. Goal

Borrow the "narrow pre-activation bar + expanded list panel" visual language from the reference screenshots and apply it to DropZone's existing file-shelving flow. The content stays file-centric; only the presentation and the drag-to-activation affordance change.

**Non-goals**
- No change to the AI/agent-task direction from the reference screenshots — content remains the user's shelved files.
- No change to shelf storage semantics (hard-link vs copy, expiry, capacity).

## 2. User Flow

1. User begins a system drag of one or more files.
2. When the cursor enters the **pre-activation zone** (the activation zone, out-set by 8 px for hysteresis), a narrow **380 × 60** pre-activation bar fades in just below the notch.
3. The bar shows: Pocky icon · primary filename (+N if more) · shelf item-count badge.
4. If the cursor continues into the existing **drop zone**, the bar morphs in place to the drop-zone affordance (same 380 × 60 frame, crossfade content).
5. On drop, the panel transitions to **shelfExpanded** at **600 × 360**, rendering either:
   - the new **ShelfListView** (default), or
   - the existing **FileShelfView** thumbnail strip.
6. Shelf dismissal is governed by `shelfPersistence` setting:
   - `autoDismiss` — collapse after 2.0 s post-drop; immediate collapse on `mouseExited`.
   - `persistent` (default) — stay open until user clicks minimize, shelf empties, presses Esc, or hovers outside for 500 ms.
7. The shelfExpanded panel has a header row with **view toggle** (list ↔ thumbnail) and **minimize** (`−`) buttons. Minimize collapses to the badged notch-attached state.

## 3. State Machine

Extends `PanelState` in `DropZonePanel.swift` with a new `.preActivated` case.

```
.hidden ─┬─► .listening ──► .preActivated ──► .expanded ──► .shelfExpanded ──► .collapsed → .hidden
         │                       │                               ▲
         │         (drag leaves)─┘                               │ (hover + non-empty shelf)
         │                                                       │
         └─(hover, non-empty shelf)──────────────────────────────┘
```

- `.preActivated` (new): 380 × 60; visible; renders `PreActivationBarView`.
- All other cases keep current semantics. The existing `.expanded` drop-zone frame is widened to **380 × 60** to match, so the morph is a content crossfade, not a size jump.
- Under `shelfPersistence = .persistent`, `.shelfExpanded` does not auto-return to `.hidden`. Transitions to `.collapsed` only via explicit user action or shelf-empty.
- Illegal transitions (e.g. `.hidden → .preActivated`) must no-op.

## 4. Components

### 4.1 New files (`DropZone/Sources/DropZoneLib/`)

| File | Role |
|---|---|
| `PreActivationBarView.swift` (SwiftUI) | 380 × 60 bar. Layout: leading Pocky icon (24×24) · primary filename (truncates middle) · optional "+N" pill · trailing shelf-count badge (hidden when count = 0). |
| `ShelfListView.swift` (SwiftUI) | Vertical scrolling list of shelf items. Row height 56, up to ~5 rows visible. Data source: `[ShelfItem]` passed in by the owner (same injection pattern as `FileShelfView`), sorted newest-first. |
| `ShelfListRowView.swift` (SwiftUI) | Single row: 32×32 icon · primary filename · 3 capsule tags (source app · file type · size). Hosts NSItemProvider for drag-out to Finder. Tags hide individually when their value is `nil`. |
| `ShelfHeaderView.swift` (SwiftUI) | 36-high header for shelfExpanded: leading title ("DropZone · N items") · trailing segmented toggle icon + minimize button. |

### 4.2 Modified files

| File | Change |
|---|---|
| `DropZonePanel.swift` | Add `.preActivated` case; add `preActivatedSize = NSSize(380, 60)`; change `shelfExpandedSize` to `NSSize(600, 360)`; widen `.expanded` drop-zone frame to 380 × 60; add `enterPreActivation(primary:extraCount:shelfCount:)` / `exitPreActivation()`; shelfExpanded container conditionally hosts `ShelfListView` or `FileShelfView` based on `SettingsManager.shelfViewMode`. |
| `GlobalDragMonitor.swift` | Add pre-activation threshold callback (`onPreActivationEnter` / `onPreActivationExit`) alongside the existing drop-zone threshold; include the dragged-file-name list (via pasteboard read) in the enter callback. Pre-activation enter threshold = activation-zone rect inset by −8 px; exit threshold = activation-zone rect (hysteresis). |
| `AppDelegate.swift` | Wire pre-activation callbacks to `DropZonePanel.enterPreActivation(...)` / `exitPreActivation()`. Post-drop dismiss policy dispatches on `SettingsManager.shelfPersistence`. |
| `NotchGeometry.swift` | Add `preActivatedSize` constant; extend `panelOrigin(for:)` to center the 380-wide bar below the notch; expose `preActivationRect(hysteresisInset:)`. |
| `SettingsManager.swift` | Add `shelfViewMode: ShelfViewMode` (`.list` default, `.thumbnail`), `shelfPersistence: ShelfPersistence` (`.persistent` default, `.autoDismiss`). Both are `@AppStorage`-backed. |
| `SettingsView.swift` | Add segmented controls for the two new settings. |
| `FileShelfManager.swift` | `ShelfItem` gains `sourceAppName: String?`, `fileSize: Int64?`, `fileExtension: String?`. Populated at intake from pasteboard + `FileManager.attributesOfItem`. Old persisted items decode with `nil` defaults. |
| `DragDestinationView.swift` | During `performDragOperation`, read `com.apple.pasteboard.source-app-bundle-identifier` from `draggingPasteboard` and forward to `FileShelfManager` with the URLs. |

## 5. Data Flow

### 5.1 Pre-activation entry

```
System drag starts
  ├─ GlobalDragMonitor observes drag session
  │   ├─ reads NSPasteboard.general fileURLs → [filename]
  │   └─ cursor enters preActivationRect
  │       └─ AppDelegate.onPreActivationEnter(fileNames)
  │           └─ DropZonePanel.enterPreActivation(
  │                 primary: fileNames.first ?? "Dragging…",
  │                 extraCount: max(0, fileNames.count - 1),
  │                 shelfCount: shelfManager.items.count)   // shelfManager is the injected instance owned by AppDelegate
  │
  ├─ cursor into drop zone → DropZonePanel.expand()   (content crossfade)
  └─ drop success → AppDelegate.handleDrop → expandShelf() + dismiss policy
```

### 5.2 Source-app extraction on drop

```swift
let bundleIDType = NSPasteboard.PasteboardType("com.apple.pasteboard.source-app-bundle-identifier")
let bundleID = sender.draggingPasteboard.string(forType: bundleIDType)
let sourceAppName: String? = bundleID.flatMap { id in
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).flatMap { url in
        Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
    }
}
```
Stored verbatim in `ShelfItem.sourceAppName`. Missing → `nil` → tag hidden.

### 5.3 Row rendering

```
[icon 32]  Filename.ext                                  [App] [PDF] [1.2 MB]
           added 28m ago · ~/Downloads
```
- Icon: QuickLook thumbnail (existing `FileThumbnailView` logic refactored for list context).
- Tags: capsule, `systemGray6` background at 20 % opacity, 11 pt label.
- Subtitle: age (`RelativeDateTimeFormatter`) + truncated parent path.

## 6. Settings UI (SettingsView.swift)

Two new segmented controls:

- **Shelf view** — `List` · `Thumbnails`
- **Stay expanded** — `Until I close it` (persistent) · `Auto-hide after drop` (autoDismiss)

Both defaults: list, persistent.

## 7. Error Handling & Edge Cases

| Scenario | Handling |
|---|---|
| Pasteboard file URLs unreadable | Show "Dragging…" + `extraCount = 0`; bar still appears. |
| Source-app bundle ID missing | `sourceAppName = nil`; App tag hidden — do not display "Unknown". |
| `FileManager.attributesOfItem` throws on intake | Snapshot `fileSize = nil`; Size tag hidden. |
| Shelf file removed externally | Row shows overlay warning icon; opening surfaces error. |
| Pre-activation threshold flicker | Hysteresis: enter rect is 8 px larger than exit rect; `DropZonePanel.enterPreActivation` also applies a 60 ms debounce. |
| Pre-activated → expanded size jump | Expanded drop-zone frame is widened to 380 × 60 to match; only the content crossfades. |
| Persistent mode stale panel | Auto-collapse only when: user minimizes, shelf empties, Esc pressed, or cursor outside panel for 500 ms. |
| autoDismiss + user re-hovers before timeout | Cancel timer on `mouseEntered`; reinstate on `mouseExited`. |
| View toggle during active drag-out | Toggle button disabled while `NSDraggingSession` is in flight. |
| Settings change while shelfExpanded visible | `shelfViewMode` change rebuilds SwiftUI subtree immediately (`@AppStorage` invalidates body); `shelfPersistence` change rebuilds timers. |

## 8. Testing

Framework: Swift Testing (`@Test`, `#expect`). All tests under `DropZone/Tests/DropZoneTests/`.

### 8.1 New test files

| File | Cases |
|---|---|
| `DropZonePanelPreActivationTests.swift` | enterPreActivation sets `.preActivated`; frame is 380×60; exitPreActivation without drop returns to `.listening`; `.preActivated → .expanded` preserves frame; illegal transitions no-op. |
| `ShelfListViewTests.swift` | N items yield N rows; `sourceAppName == nil` hides App tag; `ByteCountFormatter` output for sizes; empty-shelf empty state. |
| `PreActivationBarViewTests.swift` | `extraCount == 0` hides "+N"; long filename middle-truncates; `shelfCount == 0` hides badge. |
| `ShelfHeaderViewTests.swift` | Toggle button invokes callback; minimize button invokes callback; toggle disabled during active drag-out. |

### 8.2 Extended test files

| File | Added cases |
|---|---|
| `FileShelfManagerTests.swift` | `sourceAppName` / `fileSize` / `fileExtension` round-trip; legacy items decode with `nil` defaults. |
| `SettingsManagerTests.swift` | `shelfViewMode` defaults to `.list`; `shelfPersistence` defaults to `.persistent`; read/write round-trip. |
| `AppDelegateTests.swift` | Post-drop timer created iff `shelfPersistence == .autoDismiss`; timer cancelled on re-hover. |
| `NotchGeometryTests.swift` | `preActivatedSize == NSSize(380, 60)`; origin centered under notch; pre-activation rect is 8 px larger than activation rect. |
| `GlobalDragMonitorTests.swift` | Threshold callbacks fire on enter/exit; filename array plumbed through; missing bundle ID still delivers callback. |

### 8.3 Manual verification

- SwiftUI animation transitions (crossfade, morph)
- Real pasteboard behavior across a variety of source apps (Finder, Safari, Photos, Preview)
- Persistence feel in realistic usage

## 9. Rollout & Release

- Feature branch: `plan-6-preactivation-and-shelf-list`, cut from `main`.
- Merge checklist per CLAUDE.md applies.
- Release bump: **MINOR** (new user-visible features, backward compatible). Next tag expected `v0.4.0`.
- `CHANGELOG.md` entry `Added`: pre-activation bar; new list view for shelf; settings for view mode and stay-expanded policy.
- `README` version badge updated after tag push.

## 10. Open Questions

None remaining from brainstorming. User confirmed all decisions on 2026-04-17.
