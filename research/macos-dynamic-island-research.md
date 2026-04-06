# macOS Dynamic Island / Notch-Area Interaction Research

## 1. Existing Open-Source Projects (Reference Implementations)

### NotchDrop (★ Most Relevant)
- **Repo**: [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop)
- **What it does**: Drag-and-drop files to the notch area for temporary storage + AirDrop
- **Tech**: 100% Swift, SwiftUI + AppKit hybrid
- **License**: MIT
- **Architecture**: Files stored in RAM-resident cache; auto-expire after 1 day (configurable). Native binary <0.5% CPU idle. Supports virtual notch on notchless Macs.
- **Relevance**: **Directly matches our "dropzone" concept** — file shelf in the notch area.

### TheBoringNotch
- **Repo**: [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)
- **What it does**: Transforms notch into media control center, shelf, HUD replacements
- **Tech**: Swift 98.2%, SwiftUI-primary, Xcode 16+
- **Min macOS**: **14 Sonoma**
- **Architecture**: Modular — XPC helper for privileged ops, MediaRemoteAdapter for Now Playing, separate updater. Hover-to-expand interaction. <2% CPU during active use.
- **Shelf feature**: Inspired by NotchDrop; supports drag-and-drop + AirDrop.
- **Relevance**: Most feature-rich reference. Good architectural patterns to study.

### DynamicNotchKit (Framework)
- **Repo**: [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)
- **What it does**: Reusable Swift Package for displaying SwiftUI content from the notch
- **Min macOS**: **13 Ventura**
- **API**:
  ```swift
  let notch = DynamicNotch { ContentView() }
  await notch.expand()
  // Auto-dismiss:
  notch.show(on: NSScreen.screens[0], for: 2.0)
  ```
- **Key feature**: Automatically falls back to `.floating` style on notchless Macs.
- **Relevance**: Could be used as a dependency, or its patterns replicated.

### Atoll
- **Repo**: [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)
- **What it does**: "Command surface" in the notch — media, system insight, quick utilities
- **Tech**: SwiftUI with native animations
- **Relevance**: Good reference for expand/collapse animation patterns.

### faux-notch
- **Repo**: [twstokes/faux-notch](https://github.com/twstokes/faux-notch)
- **What it does**: Minimal example of rendering a fake notch with AppKit + SwiftUI
- **Relevance**: Simplest reference for understanding the window-over-notch technique.

---

## 2. Notch Detection & Screen Geometry APIs

### Key APIs (macOS 12+)

| API | Purpose |
|-----|---------|
| `NSScreen.safeAreaInsets` | Distances from edges where content is obscured (`.top > 0` = has notch) |
| `NSScreen.auxiliaryTopLeftArea` | Unobscured rect left of the notch |
| `NSScreen.auxiliaryTopRightArea` | Unobscured rect right of the notch |
| `NSScreen.frame` | Full screen bounds |
| `NSScreen.visibleFrame` | Usable area excluding Dock and menu bar |

### Notch Detection Pattern
```swift
extension NSScreen {
    var hasNotch: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top != 0
    }
    
    var notchRect: NSRect? {
        guard hasNotch else { return nil }
        let left = auxiliaryTopLeftArea
        let right = auxiliaryTopRightArea
        // Notch occupies the gap between left and right auxiliary areas
        return NSRect(
            x: left.maxX,
            y: frame.maxY - safeAreaInsets.top,
            width: right.minX - left.maxX,
            height: safeAreaInsets.top
        )
    }
}
```

**Source**: [Apple Developer Documentation — safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets), [auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/3882915-auxiliarytopleftarea)

---

## 3. Floating Window / Panel Techniques

### NSPanel Approach (Recommended for Notch Overlay)

The standard pattern from [Cindori's floating panel guide](https://cindori.com/developer/floating-panel):

```swift
class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        // Critical settings:
        isFloatingPanel = true
        level = .floating              // Above all normal windows
        // Or: level = .popUpMenu      // Above floating windows too
        collectionBehavior.insert(.fullScreenAuxiliary)  // Works in fullscreen
        collectionBehavior.insert(.stationary)            // Stays on screen switch
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        
        isMovableByWindowBackground = false  // We control positioning
        hidesOnDeactivate = false             // Stay visible always
    }
    
    // Allow key events without stealing app focus
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

### Bridging SwiftUI Content
```swift
panel.contentView = NSHostingView(rootView:
    NotchContentView()
        .ignoresSafeArea()
)
```

### Window Level Hierarchy
| Level | Use Case |
|-------|----------|
| `.normal` | Regular windows |
| `.floating` | Always-on-top panels |
| `.popUpMenu` | Above floating windows |
| `.screenSaver` | Above everything |

**For a notch overlay**: Use `.floating` or `.statusBar` level to stay above app windows but below system alerts.

---

## 4. Drag-and-Drop APIs

### Two Approaches

#### A. AppKit: NSDraggingDestination (Lower-level, More Control)

```swift
class DropZoneView: NSView {
    override func awakeFromNib() {
        registerForDraggedTypes([.fileURL, .string, .URL])
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Highlight drop zone
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Remove highlight
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }
        
        // Process dropped files
        handleDroppedFiles(items)
        return true
    }
}
```

**Pros**: Full control over drag visualization, hover states, pasteboard reading. Battle-tested.
**Cons**: Requires NSView subclass; more boilerplate.

**Sources**: [AppCoda NSPasteboard Tutorial](https://www.appcoda.com/nspasteboard-macos/), [Kodeco Drag and Drop Tutorial](https://www.kodeco.com/1016-drag-and-drop-tutorial-for-macos), [Apple Drag and Drop Docs](https://developer.apple.com/documentation/appkit/drag-and-drop)

#### B. SwiftUI: .onDrop / .dropDestination (Higher-level, Less Control)

```swift
// Modern approach (macOS 13+)
.dropDestination(for: URL.self) { urls, location in
    handleDroppedFiles(urls)
    return true
}

// Older approach
.onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
    // Extract URLs from NSItemProvider
}
```

**Pros**: Declarative, less code, integrates with SwiftUI animations.
**Cons**: Less control over drag visualization; no native "highlight on hover" like AppKit. `NSItemProvider`-based extraction is async and slightly awkward.

### Recommendation for Notch Drop Zone

**Use AppKit NSDraggingDestination wrapped in SwiftUI** — the notch overlay window itself will be an NSPanel (AppKit), so registering it as a drag destination is natural. SwiftUI handles the UI content inside. This hybrid approach gives full drag-and-drop control while keeping the UI declarative.

---

## 5. Recommended Tech Stack

### Language & Frameworks

| Component | Recommendation | Rationale |
|-----------|---------------|-----------|
| **Language** | Swift | All reference projects use Swift; best macOS API access |
| **UI Layer** | SwiftUI (primary) | Declarative, animation-friendly, used by all modern notch apps |
| **Window Management** | AppKit (NSPanel) | SwiftUI cannot create borderless floating panels alone |
| **Drag & Drop** | AppKit (NSDraggingDestination) | Full control; NSPanel is already AppKit |
| **Animations** | SwiftUI + Core Animation | SwiftUI for content transitions; CA for window-level effects |
| **File Management** | Foundation (FileManager) | Standard; sandboxing support |

### Architecture Pattern

```
┌─────────────────────────────────────────┐
│              App Delegate               │
│  (NSApplicationDelegate, lifecycle)     │
├─────────────────────────────────────────┤
│         NotchPanel (NSPanel)            │
│  - Window positioning over notch        │
│  - Drag destination registration        │
│  - Mouse tracking (hover detection)     │
│  - Window level management              │
├─────────────────────────────────────────┤
│      NSHostingView ← SwiftUI Views      │
│  ┌─────────────────────────────────┐    │
│  │  NotchOverlayView (SwiftUI)     │    │
│  │  - Collapsed state (notch shape)│    │
│  │  - Expanded state (shelf/grid)  │    │
│  │  - Drop highlight animations    │    │
│  │  - File thumbnails              │    │
│  └─────────────────────────────────┘    │
├─────────────────────────────────────────┤
│         DropZoneManager (Model)         │
│  - Temporary file storage               │
│  - Auto-expiration timer                 │
│  - File metadata / thumbnails            │
│  - AirDrop integration (optional)        │
└─────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **NSPanel, not NSWindow**: Non-activating panel that receives drops without stealing focus
2. **Hybrid AppKit+SwiftUI**: AppKit for window chrome and drag handling; SwiftUI for content
3. **Observable pattern**: `@Observable` / `ObservableObject` for file shelf state
4. **Mouse tracking area**: `NSTrackingArea` on the panel for hover-to-expand behavior
5. **Screen observer**: Watch for display configuration changes to reposition

---

## 6. Minimum macOS Version

| Target | Trade-offs |
|--------|-----------|
| **macOS 12 Monterey** | Minimum for `safeAreaInsets` notch detection. Limited SwiftUI features. |
| **macOS 13 Ventura** ✅ | Adds `dropDestination`, better SwiftUI navigation, `@Observable` preview. DynamicNotchKit targets this. |
| **macOS 14 Sonoma** ⭐ | Full `@Observable` macro, SwiftUI improvements, `TipKit`. TheBoringNotch targets this. Most notch MacBooks ship with ≥14. |
| **macOS 15 Sequoia** | Newest; limits audience. |

### **Recommendation: macOS 14 Sonoma**

**Rationale**:
- All MacBooks with a notch (2021+) can run macOS 14
- `@Observable` macro simplifies state management significantly
- SwiftUI in macOS 14 has critical fixes for animations and layout
- TheBoringNotch (the most mature reference) targets macOS 14
- Targeting 13 gains very few additional users while adding compatibility burden

---

## 7. Information Confidence Assessment

| Finding | Confidence | Source Quality |
|---------|-----------|---------------|
| NSPanel floating window technique | ⭐⭐⭐⭐⭐ | Apple docs + multiple implementations |
| NotchDrop architecture | ⭐⭐⭐⭐ | Open source (MIT), verified GitHub |
| TheBoringNotch patterns | ⭐⭐⭐⭐ | Open source, active development |
| DynamicNotchKit API | ⭐⭐⭐⭐⭐ | Published Swift Package with docs |
| NSScreen notch detection | ⭐⭐⭐⭐⭐ | Apple Developer Documentation |
| Drag-and-drop APIs | ⭐⭐⭐⭐⭐ | Apple docs + established tutorials |
| macOS 14 as minimum | ⭐⭐⭐⭐ | Analysis of reference projects + market data |
| Performance claims (<2% CPU) | ⭐⭐⭐ | Self-reported by project authors |

---

## 8. Key Risks & Considerations

1. **No official Apple API for notch interaction** — All implementations use standard NSPanel/NSWindow positioned over the notch area. Apple could change notch behavior in future macOS versions.
2. **Menu bar manager conflicts** — Need to handle coexistence with Bartender, iStatMenus, etc.
3. **Multi-monitor** — Must handle screens with and without notches; reposition on display changes.
4. **Accessibility** — Floating panels should support VoiceOver; ensure drag-drop has keyboard alternatives.
5. **App Store review** — Apps that overlay the notch have been approved (NotchDrop is on App Store), but positioning windows in the menu bar area could face scrutiny.
