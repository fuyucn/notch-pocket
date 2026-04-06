# DropZone — Product Design Document

> A macOS app that transforms the notch into a temporary file shelf, enabling frictionless cross-context file transfers via drag-and-drop.

**Version**: 1.0  
**Last Updated**: 2026-04-06  
**Status**: Draft  
**Minimum macOS**: 14 Sonoma

---

## Table of Contents

1. [Product Vision](#1-product-vision)
2. [User Stories](#2-user-stories)
3. [UX Flow](#3-ux-flow)
4. [UI Specifications](#4-ui-specifications)
5. [Technical Architecture](#5-technical-architecture)
6. [Edge Cases](#6-edge-cases)
7. [Accessibility](#7-accessibility)
8. [Testing Strategy](#8-testing-strategy)

---

## 1. Product Vision

### Problem

Moving files between different locations on macOS is friction-heavy. Users must either:
- Hold the mouse button while navigating between windows or spaces (tiring, error-prone)
- Open two Finder windows side by side (breaks workflow)
- Use the Desktop as a temporary staging area (clutters workspace)

### Solution

**DropZone** turns the MacBook notch area into a "Dynamic Island" — a persistent, always-accessible drop zone. Users drag files onto the notch, release them, switch to their destination, then drag the files back out. No button-holding across windows. No Desktop clutter.

### Core Principles

| Principle | Description |
|-----------|-------------|
| **Zero-friction** | The notch is always there — no app switching, no keyboard shortcuts needed to start |
| **Non-intrusive** | Invisible when not needed; appears only during drag operations or on hover |
| **Temporary by nature** | Files auto-expire after a configurable period (default: 1 hour) |
| **Native feel** | Animations, visuals, and interactions match macOS system conventions |

### Success Metrics

- **Activation latency**: < 100ms from drag entering notch area to visual feedback
- **CPU idle**: < 0.5% when no interaction
- **CPU active**: < 2% during drag operations
- **Memory footprint**: < 30MB base (excluding cached thumbnails)

---

## 2. User Stories

### Primary

| ID | As a... | I want to... | So that... | Priority |
|----|---------|-------------|-----------|----------|
| US-1 | Mac user | drag a file to the notch and drop it | I can release the mouse and switch context freely | P0 |
| US-2 | Mac user | see a visual indicator when dragging near the notch | I know the drop zone is available | P0 |
| US-3 | Mac user | drag a file back out from the notch shelf | I can place it in a new destination | P0 |
| US-4 | Mac user | see thumbnails of shelved files | I can identify which file I need | P0 |
| US-5 | Mac user | drop multiple files at once | I can batch-transfer files | P0 |
| US-6 | Mac user | have files auto-expire from the shelf | the shelf doesn't accumulate clutter forever | P1 |

### Secondary

| ID | As a... | I want to... | So that... | Priority |
|----|---------|-------------|-----------|----------|
| US-7 | Mac user | hover over the notch to see shelved files | I can check what's stored without dragging | P1 |
| US-8 | Mac user | remove individual files from the shelf | I can clean up files I no longer need | P1 |
| US-9 | Mac user | clear all files from the shelf at once | I can start fresh quickly | P2 |
| US-10 | Mac user | use DropZone on a Mac without a notch | the app is useful on older/external displays | P2 |
| US-11 | Mac user | configure the auto-expire duration | I can match the shelf to my workflow | P2 |
| US-12 | Mac user | use DropZone across multiple monitors | file shelving works regardless of which screen I'm on | P2 |

---

## 3. UX Flow

### 3.1 Primary Flow: Drag → Drop → Switch → Retrieve

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. USER DRAGS FILE           2. ENTERS NOTCH ZONE              │
│  ───────────────────          ──────────────────────             │
│  User picks up file(s)       Drag cursor enters the notch       │
│  from Finder, Desktop,       detection area (notch height +     │
│  or any app                  40pt padding below)                 │
│                                                                 │
│         │                              │                        │
│         ▼                              ▼                        │
│                                                                 │
│  3. DYNAMIC ISLAND APPEARS   4. USER DROPS FILE                 │
│  ─────────────────────────   ──────────────────                 │
│  Notch area expands with     Files are added to the shelf.      │
│  smooth animation into a     Drop zone shows brief "Added"      │
│  rounded-rect drop zone.     confirmation animation.            │
│  Visual: glow + scale-up.    Shelf collapses back to notch.     │
│                                                                 │
│         │                              │                        │
│         ▼                              ▼                        │
│                                                                 │
│  5. USER SWITCHES CONTEXT    6. USER RETRIEVES FILES            │
│  ────────────────────────    ───────────────────────            │
│  User navigates to target    User hovers over notch → shelf     │
│  app/folder/space. No file   expands showing thumbnails.        │
│  held — hands are free.      Drags file(s) out to destination.  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 State Machine

```
                    ┌──────────┐
                    │  HIDDEN  │ ◄── App launch (no interaction)
                    └────┬─────┘
                         │ System drag session begins
                         ▼
                   ┌────────────┐
                   │  LISTENING │ ◄── Invisible, tracking cursor position
                   └─────┬──────┘
                         │ Cursor enters notch zone
                         ▼
                   ┌────────────┐
             ┌───► │  EXPANDED  │ ◄── Drop zone visible, accepting drops
             │     └──┬──────┬──┘
             │        │      │ Cursor exits zone (no drop)
             │        │      ▼
             │        │  ┌──────────┐
             │        │  │ COLLAPSE │ → back to HIDDEN/LISTENING
             │        │  └──────────┘
             │        │
             │        │ File(s) dropped
             │        ▼
             │   ┌───────────┐
             │   │ SHELF     │ ◄── Shows file count badge on notch
             │   └──┬────┬───┘
             │      │    │ Hover over notch
             │      │    ▼
             │      │ ┌──────────────┐
             │      │ │ SHELF_EXPAND │ ◄── Full shelf with thumbnails
             │      │ └──────┬───────┘
             │      │        │ Drag file out / All files removed
             │      │        ▼
             │      │    (back to SHELF or HIDDEN)
             │      │
             │      │ All files expire
             │      ▼
             │   ┌──────────┐
             └── │  HIDDEN  │
                 └──────────┘
```

### 3.3 Interaction Details

| Trigger | Action | Animation |
|---------|--------|-----------|
| System drag begins anywhere | App enters LISTENING state | None (invisible) |
| Drag cursor within 40pt below notch | EXPANDED state: drop zone appears | Notch morphs outward: 300ms ease-out spring |
| File dropped on zone | Brief "✓ Added" pulse, collapse to SHELF | 200ms scale pulse, then 400ms collapse |
| Drag cursor leaves zone (no drop) | Collapse back | 250ms ease-in |
| Hover over notch (files shelved) | SHELF_EXPAND: grid of thumbnails | 300ms spring expansion |
| Mouse leaves expanded shelf | Collapse shelf | 400ms ease-in-out |
| Drag file out of shelf | File follows cursor, removed from shelf | Standard macOS drag image |
| Last file removed/expired | Return to HIDDEN | 300ms fade-out |

---

## 4. UI Specifications

### 4.1 Notch Area Detection

The activation zone is the **notch rectangle extended 40pt downward**:

```
Screen top edge
├──────────┬─────────────────┬──────────┤
│ Menu bar │  ███ NOTCH ███  │ Menu bar │
│  (left)  │  ███████████    │ (right)  │
├──────────┴────────┬────────┴──────────┤
│                   │                    │
│   +40pt padding   │  ← Activation     │
│   below notch     │     zone extends  │
│                   │     here          │
├───────────────────┴────────────────────┤
```

**Detection logic**:
```
notchRect = gap between auxiliaryTopLeftArea and auxiliaryTopRightArea
activationRect = notchRect expanded by:
  - 40pt below (easier to reach)
  - 20pt left/right (forgiving horizontal aim)
```

### 4.2 Drop Zone (EXPANDED State)

| Property | Value |
|----------|-------|
| Shape | Rounded rectangle matching notch corners (radius ~18pt) |
| Size | Expands from notch dimensions (~200×32pt) to ~320×80pt |
| Background | `NSVisualEffectView` with `.hudWindow` material (dark translucent) |
| Border | 1pt stroke, `white @ 15%` opacity |
| Drop highlight | Animated dashed border, `accentColor @ 60%` |
| Position | Centered horizontally on notch, grows downward |

**Visual States**:
- **Idle expanded**: Dark translucent pill shape with "Drop files here" label
- **Drag hovering**: Border becomes dashed animated line, subtle inner glow
- **Drop accepted**: Green checkmark pulse, file count updates

### 4.3 Shelf View (SHELF_EXPAND State)

| Property | Value |
|----------|-------|
| Max width | 480pt |
| Max height | 320pt (scrollable if more files) |
| Layout | Grid — 4 columns, 80×80pt cells |
| Thumbnail size | 64×64pt with 8pt padding |
| File name | Truncated to 2 lines, 10pt system font, centered below thumbnail |
| Background | Same `hudWindow` material as drop zone |
| Corner radius | 18pt |
| Shadow | 0 4pt 20pt `black @ 30%` |

**Shelf Badge** (collapsed SHELF state):
- Small pill overlaid on right side of notch area
- Shows file count (e.g., "3")
- Color: `accentColor` background, white text
- Size: auto-fit, minimum 20×20pt

### 4.4 Thumbnails

| File Type | Thumbnail Source |
|-----------|-----------------|
| Images (jpg, png, gif, etc.) | QuickLook thumbnail via `QLThumbnailGenerator` |
| PDFs | First page preview via `QLThumbnailGenerator` |
| Videos | First frame via `AVAssetImageGenerator` |
| Folders | System folder icon |
| Other files | System file-type icon via `NSWorkspace.shared.icon(forFile:)` |

Thumbnail generation is **async** — show a placeholder (file-type icon) until the thumbnail loads.

### 4.5 Animation Specifications

| Animation | Duration | Curve | Details |
|-----------|----------|-------|---------|
| Notch → Expanded | 300ms | Spring (damping: 0.75, response: 0.3) | Scale + opacity from notch rect to full drop zone |
| Expanded → Collapsed | 250ms | Ease-in (0.4, 0, 1, 1) | Reverse of expand |
| Drop confirmation | 200ms | Ease-out | Scale pulse to 1.1x then back to 1.0x |
| Shelf expand | 300ms | Spring (damping: 0.8, response: 0.35) | Width + height grow, thumbnails fade in with 50ms stagger |
| Shelf collapse | 400ms | Ease-in-out | Reverse, no stagger |
| File badge count change | 150ms | Spring | Number scales up then settles |
| File removal from shelf | 250ms | Ease-out | Shrink + fade out, remaining files reflow |

---

## 5. Technical Architecture

### 5.1 Project Structure

```
DropZone/
├── DropZoneApp.swift              # @main, app lifecycle
├── AppDelegate.swift              # NSApplicationDelegate, setup
│
├── Panel/
│   ├── NotchPanel.swift           # NSPanel subclass (floating, non-activating)
│   ├── NotchPanelController.swift # Positioning, screen observation, show/hide
│   └── DragDestinationView.swift  # NSView implementing NSDraggingDestination
│
├── Views/
│   ├── DropZoneView.swift         # SwiftUI: expanded drop zone UI
│   ├── ShelfView.swift            # SwiftUI: file shelf grid
│   ├── ShelfItemView.swift        # SwiftUI: individual file thumbnail + name
│   ├── BadgeView.swift            # SwiftUI: file count badge on notch
│   └── SettingsView.swift         # SwiftUI: preferences window
│
├── Models/
│   ├── ShelfItem.swift            # File metadata model (URL, thumbnail, timestamp)
│   ├── ShelfStore.swift           # @Observable: file shelf state, add/remove/expire
│   └── DragState.swift            # @Observable: current drag interaction state
│
├── Services/
│   ├── ScreenDetector.swift       # Notch detection, screen geometry, multi-monitor
│   ├── ThumbnailService.swift     # Async thumbnail generation (QLThumbnailGenerator)
│   ├── FileShelfService.swift     # File copy/move to temp storage, expiry timer
│   └── DragMonitor.swift          # Global drag session monitoring
│
├── Utilities/
│   ├── Constants.swift            # Animation durations, sizes, padding values
│   └── NSScreen+Notch.swift       # NSScreen extension for notch geometry
│
├── Resources/
│   ├── Assets.xcassets            # App icon, accent colors
│   └── Localizable.strings        # Localization
│
└── Tests/
    ├── ShelfStoreTests.swift
    ├── ScreenDetectorTests.swift
    ├── FileShelfServiceTests.swift
    ├── ThumbnailServiceTests.swift
    └── DragStateTests.swift
```

### 5.2 Component Architecture

```
┌───────────────────────────────────────────────────────┐
│                    AppDelegate                         │
│  - Creates NotchPanelController on launch              │
│  - Registers global drag monitor                       │
│  - Manages app lifecycle (login item, menu bar icon)   │
└────────────────────┬──────────────────────────────────┘
                     │ owns
                     ▼
┌───────────────────────────────────────────────────────┐
│              NotchPanelController                      │
│  - Creates & positions NotchPanel over notch           │
│  - Observes NSScreen changes (display connect/remove)  │
│  - Coordinates DragState with panel visibility          │
└────┬───────────────────────────────────┬──────────────┘
     │ owns                              │ owns
     ▼                                   ▼
┌──────────────┐              ┌──────────────────────┐
│  NotchPanel  │              │  DragMonitor         │
│  (NSPanel)   │              │  (NSEvent.addGlobal) │
│              │              │  - Detects system    │
│  ┌────────┐  │              │    drag sessions     │
│  │Drag    │  │              │  - Tracks cursor     │
│  │Dest.   │  │◄─────────── │    position           │
│  │View    │  │  notifies   └──────────────────────┘
│  └────────┘  │
│  ┌────────┐  │
│  │Hosting │  │
│  │View    │  │
│  │(SwiftUI│  │
│  └────────┘  │
└──────────────┘
       │ displays
       ▼
┌─────────────────────────┐     ┌─────────────────────┐
│  DropZoneView (SwiftUI) │     │  ShelfStore          │
│  ShelfView (SwiftUI)    │────►│  (@Observable)       │
│  BadgeView (SwiftUI)    │     │  - items: [ShelfItem]│
└─────────────────────────┘     │  - add/remove/clear  │
                                │  - expiry timer      │
                                └──────────┬──────────┘
                                           │ uses
                                           ▼
                          ┌─────────────────────────────┐
                          │  FileShelfService            │
                          │  - Copies files to temp dir  │
                          │  - Manages temp storage      │
                          │  - Cleans up on expiry       │
                          └─────────────────────────────┘
```

### 5.3 Window Management

**Panel positioning** (recalculated on screen changes):

```swift
func positionPanel(on screen: NSScreen) {
    guard let notchRect = screen.notchRect else {
        // Fallback: center top of screen
        positionAsFallback(on: screen)
        return
    }
    
    // Panel origin: aligned to notch, extended downward
    let panelRect = NSRect(
        x: notchRect.midX - panelWidth / 2,
        y: notchRect.minY - expandedHeight,
        width: panelWidth,
        height: notchRect.height + expandedHeight
    )
    panel.setFrame(panelRect, display: true, animate: true)
}
```

**Screen change observation**:
- `NSApplication.didChangeScreenParametersNotification` — monitors connect/disconnect
- Reposition panel whenever the main screen (with notch) changes

### 5.4 Drag-and-Drop Pipeline

```
1. DETECTION
   NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged])
   → Check if a system drag session is active
   → Alternative: CGEventTap for earlier detection

2. ACTIVATION  
   DragMonitor tracks cursor position against activation rect
   → When cursor enters zone: NotchPanelController shows panel
   → Panel's DragDestinationView receives draggingEntered()

3. DROP PROCESSING
   performDragOperation() reads pasteboard:
   → .fileURL items → copy to temp storage
   → .string items → create text clipping file
   → Update ShelfStore

4. RETRIEVAL
   Shelf items are draggable (NSDraggingSource):
   → ShelfItemView provides NSDragging promise
   → On drag-out: provide file URL from temp storage
   → After successful drag: optionally remove from shelf
```

### 5.5 File Temporary Storage

| Aspect | Design |
|--------|--------|
| **Location** | `~/Library/Caches/com.dropzone.app/shelf/` |
| **Strategy** | Hard-link when on same volume; copy when cross-volume |
| **Naming** | `{UUID}/{original-filename}` — preserves original name |
| **Max total size** | 2GB default (configurable in Settings) |
| **Expiry** | Timer-based: default 1 hour, configurable 15min–24hr |
| **Cleanup** | On expiry, on app quit, and on explicit user removal |

**Why hard-link first**: Avoids doubling disk usage for same-volume files. Hard-links share the same data blocks, so the file persists even if the user moves/deletes the original during the shelf period.

### 5.6 Global Drag Detection

The key challenge: detecting that a system-wide drag session is in progress before the cursor enters our window.

**Approach**: Monitor `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged)` combined with checking `NSPasteboard(name: .drag)` for content. When a global drag is detected with file URL content, transition to LISTENING state.

**Fallback**: If global monitoring is insufficient (sandboxing constraints), use `CGEventTap` with `kCGEventOtherMouseDragged` — requires Accessibility permission.

---

## 6. Edge Cases

### 6.1 Multiple Files

| Scenario | Behavior |
|----------|----------|
| Drop 5 files at once | All added to shelf; grid expands to show all |
| Drop more files onto existing shelf | Appended to shelf; count badge updates |
| Shelf reaches max items (default: 50) | Oldest items auto-removed to make room; toast notification shown |
| Drag multiple files out | User can select multiple items in expanded shelf, drag them together |

### 6.2 Large Files

| Scenario | Behavior |
|----------|----------|
| Single file > 500MB | Show warning toast: "Large file — shelf storage is temporary" |
| Total shelf size > 2GB limit | Reject drop; toast: "Shelf full. Remove files to add more." |
| File copy in progress (cross-volume) | Show progress indicator on thumbnail; file available after copy completes |
| Hard-link fails (cross-volume, APFS→HFS+) | Automatically fall back to file copy |

### 6.3 Notch vs Non-Notch Macs

| Display Type | Behavior |
|-------------|----------|
| Built-in with notch (MacBook Pro 2021+, MacBook Air 2022+) | Full notch-aligned experience |
| Built-in without notch (older MacBooks, Mac Mini/Studio/Pro display) | Floating pill at top-center of screen, styled to match system |
| External display (no notch) | Floating pill at top-center; can be repositioned |
| Mixed: notch built-in + external | Notch on built-in; floating pill on externals; user can choose primary |

**Fallback floating pill**:
- Width: 200pt, height: 32pt
- Position: centered horizontally, 4pt below menu bar
- Same material/style as notch overlay
- Subtle always-visible idle state (thin dark line) vs notch's true invisibility

### 6.4 Multi-Monitor

| Scenario | Behavior |
|----------|----------|
| Two screens, one with notch | DropZone on notch screen by default; option to enable on both |
| Two screens, neither with notch | Floating pill on primary screen; option to enable on both |
| Screen connected/disconnected | Panel repositions within 500ms; files persist across screen changes |
| Drag across screens | Activation zone exists on all enabled screens; single shared shelf |
| Spaces / Mission Control | Panel stays visible across all Spaces (`.canJoinAllSpaces`) |

### 6.5 Conflict Handling

| Scenario | Behavior |
|----------|----------|
| Menu bar app overlaps notch area | DropZone activation zone has lower priority; user drag intent (moving toward notch specifically) used to disambiguate |
| Full-screen app active | Panel shows above full-screen app (`fullScreenAuxiliary` collection behavior) |
| Screen saver / lock screen | Panel hidden; files preserved; reappears after unlock |
| App crash / force quit | Temp files remain in cache dir; cleaned up on next launch |
| Drag from sandboxed app | Use security-scoped bookmarks if app is sandboxed; otherwise standard file URLs |

### 6.6 File Type Handling

| File Type | Drop Behavior |
|-----------|---------------|
| Regular files | Copy/hard-link to temp storage |
| Folders | Entire folder tree copied/linked |
| Aliases / Symlinks | Resolve to original; copy the original |
| Text selections (no file) | Create `.txt` clipping file with content |
| URLs dragged from browser | Create `.webloc` file |
| Images dragged from web | Save as image file with inferred extension |

---

## 7. Accessibility

### 7.1 VoiceOver Support

| Element | Accessibility Label | Role |
|---------|-------------------|------|
| Drop zone (expanded) | "DropZone file shelf. Drop files here for temporary storage." | Group |
| Shelf item | "{filename}, {file type}, added {relative time}" | Button |
| File count badge | "{N} files in DropZone shelf" | Static text |
| Clear all button | "Clear all files from shelf" | Button |
| Remove file button | "Remove {filename} from shelf" | Button |

### 7.2 Keyboard Alternatives

Since drag-and-drop is inherently mouse-driven, provide keyboard alternatives:

| Shortcut | Action |
|----------|--------|
| `⌘ + Shift + D` | Open shelf (global hotkey, configurable) |
| `⌘ + V` in expanded shelf | Paste files from clipboard to shelf |
| `⌘ + C` on selected shelf item | Copy file back to clipboard |
| `↑↓←→` in expanded shelf | Navigate between shelf items |
| `Delete` on selected item | Remove from shelf |
| `⌘ + Delete` | Clear all shelf items |
| `Escape` | Close expanded shelf |

### 7.3 Visual Accessibility

| Feature | Implementation |
|---------|---------------|
| Reduce Motion | Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`; use fade instead of spring animations |
| Increase Contrast | Thicker borders, higher-opacity backgrounds when system contrast is increased |
| Color independence | Never use color alone to convey state; always pair with icons/labels |
| Dynamic Type | Shelf item labels respect system text size settings |

### 7.4 Reduce Transparency

When `accessibilityDisplayShouldReduceTransparency` is true, replace `NSVisualEffectView` materials with solid dark/light backgrounds matching the system appearance.

---

## 8. Testing Strategy

### 8.1 Unit Tests

| Module | Test Focus |
|--------|-----------|
| `ShelfStore` | Add/remove items, expiry logic, max capacity enforcement, persistence |
| `ScreenDetector` | Notch detection on various screen configs, fallback behavior |
| `FileShelfService` | Hard-link vs copy decision, cleanup on expiry, temp dir management |
| `ThumbnailService` | Thumbnail generation for various file types, placeholder fallback |
| `DragState` | State machine transitions, edge case states |
| `ShelfItem` | Model initialization, equatable conformance, timestamp handling |

### 8.2 Integration Tests

| Test | Description |
|------|-------------|
| Drop → Shelf → Retrieve | Full cycle: simulate drop, verify shelf state, simulate drag-out |
| Multi-file batch drop | Drop N files, verify all appear in shelf with correct metadata |
| Expiry cycle | Add file, advance timer, verify file removed and temp storage cleaned |
| Screen change | Simulate screen parameter change, verify panel repositions correctly |

### 8.3 UI Tests (XCUITest)

| Test | Description |
|------|-------------|
| Shelf expansion | Hover over notch area, verify shelf appears with correct items |
| Keyboard navigation | Use shortcuts to open shelf, navigate items, copy/remove |
| Settings persistence | Change expiry time, restart app, verify setting persists |
| VoiceOver labels | Verify all interactive elements have accessibility labels |

### 8.4 Performance Tests

| Metric | Target | Test Method |
|--------|--------|-------------|
| Idle CPU | < 0.5% | XCTest `measure` block, 60s idle sample |
| Active CPU (drag) | < 2% | Measure during simulated drag operations |
| Memory (empty shelf) | < 30MB | Xcode Memory Gauge baseline |
| Memory (50 items) | < 80MB | Load 50 items with thumbnails, measure |
| Panel show latency | < 100ms | Timestamp from drag-enter to panel visible |
| Thumbnail generation | < 500ms per file | Measure async thumbnail completion time |

---

## Appendix A: Configuration Defaults

| Setting | Default | Range |
|---------|---------|-------|
| Auto-expire duration | 1 hour | 15 min – 24 hours |
| Max shelf items | 50 | 10 – 200 |
| Max shelf storage | 2 GB | 500 MB – 10 GB |
| Launch at login | Off | On/Off |
| Show on all displays | Off | On/Off |
| Global shortcut | `⌘ + Shift + D` | Customizable |
| Activation zone padding | 40pt below, 20pt sides | Not user-configurable |
| Sound effects | On | On/Off |

## Appendix B: Reference Projects

| Project | Relevance | License |
|---------|-----------|---------|
| [NotchDrop](https://github.com/Lakr233/NotchDrop) | Direct inspiration — file shelf in notch | MIT |
| [TheBoringNotch](https://github.com/TheBoredTeam/boring.notch) | Architecture patterns, shelf feature | MIT |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | Reusable notch UI framework | MIT |
| [Atoll](https://github.com/Ebullioscopic/Atoll) | Animation patterns | MIT |
