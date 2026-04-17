# Drag Pre-Activation Bar & Shelf List Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a narrow 380×60 pre-activation bar that appears when a drag enters an out-set notch zone, morph it into the drop zone as the cursor continues in, and replace the post-drop shelf with a new 600×360 list-view panel (keeping the existing thumbnail view as a toggle).

**Architecture:** Extend `PanelState` with `.preActivated`. `GlobalDragMonitor` gets a second, outer threshold (pre-activation rect = activation rect + 8 px) and sniffs pasteboard filenames. `DropZonePanel` hosts two new SwiftUI views (`PreActivationBarView`, `ShelfListView`) alongside the existing AppKit `FileShelfView`, chosen at render time from a new `SettingsManager.shelfViewMode` setting. A new `SettingsManager.shelfPersistence` setting controls whether the shelf auto-dismisses or stays open. A header (`ShelfHeaderView`) adds a view-toggle and minimize button on top of shelf-expanded.

**Tech Stack:** Swift 6.0, macOS 14+, AppKit (NSPanel/NSView), SwiftUI (NSHostingView), Swift Testing (`@Test`/`#expect`), Swift Package Manager.

**Spec reference:** `docs/superpowers/specs/2026-04-17-drag-preactivation-and-shelf-redesign-design.md`

**Branching (per `CLAUDE.md`):** All work happens on a new branch `plan-6-preactivation-and-shelf-list` cut from `main`. Do not commit to `main` directly.

---

## Prerequisites: Create the feature branch

- [ ] **Step 0.1: Ensure a clean working tree and cut the feature branch from `main`**

```bash
cd /Users/yfu/Developer/dropzone
git status
# If there are uncommitted changes unrelated to this plan, stash or commit them first.
git fetch origin
git checkout main
git pull --ff-only origin main
git checkout -b plan-6-preactivation-and-shelf-list
```

Expected: branch `plan-6-preactivation-and-shelf-list` is checked out and tracks nothing yet.

- [ ] **Step 0.2: Sanity-check tests pass before any changes**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
swift test 2>&1 | tail -40
```

Expected: all existing tests pass. If not, STOP and fix/report before proceeding.

---

## Task 1: Extend `ShelfItem` with `sourceAppName` and `fileExtension`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/FileShelfManager.swift`
- Modify: `DropZone/Tests/DropZoneTests/FileShelfManagerTests.swift`

- [ ] **Step 1.1: Write failing tests for the new fields**

Append to `DropZone/Tests/DropZoneTests/FileShelfManagerTests.swift` (near existing `ShelfItem`-related tests):

```swift
@Test @MainActor
func shelfItemDefaultsSourceAppAndExtensionToNil() {
    let item = ShelfItem(
        originalURL: URL(fileURLWithPath: "/tmp/foo.pdf"),
        shelfURL: URL(fileURLWithPath: "/tmp/shelf/foo.pdf"),
        displayName: "foo.pdf",
        fileSize: 42
    )
    #expect(item.sourceAppName == nil)
    #expect(item.fileExtension == nil)
}

@Test @MainActor
func shelfItemStoresSourceAppAndExtension() {
    let item = ShelfItem(
        originalURL: URL(fileURLWithPath: "/tmp/foo.pdf"),
        shelfURL: URL(fileURLWithPath: "/tmp/shelf/foo.pdf"),
        displayName: "foo.pdf",
        fileSize: 42,
        sourceAppName: "Finder",
        fileExtension: "pdf"
    )
    #expect(item.sourceAppName == "Finder")
    #expect(item.fileExtension == "pdf")
}

@Test @MainActor
func addFilesPopulatesFileExtension() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let src = tmp.appendingPathComponent("note.txt")
    try "hello".write(to: src, atomically: true, encoding: .utf8)

    let shelfDir = tmp.appendingPathComponent("shelf", isDirectory: true)
    let manager = FileShelfManager(directory: shelfDir)
    try manager.ensureShelfDirectory()

    let added = manager.addFiles(from: [src])
    #expect(added.count == 1)
    #expect(added.first?.fileExtension == "txt")
}
```

- [ ] **Step 1.2: Run tests — they must fail for the right reason**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
swift test --filter "FileShelfManagerTests.shelfItemDefaultsSourceAppAndExtensionToNil|FileShelfManagerTests.shelfItemStoresSourceAppAndExtension|FileShelfManagerTests.addFilesPopulatesFileExtension" 2>&1 | tail -30
```

Expected: fails to compile (unknown initializer arguments / unknown properties).

- [ ] **Step 1.3: Add the new fields to `ShelfItem`**

In `DropZone/Sources/DropZoneLib/FileShelfManager.swift`, replace the `ShelfItem` struct (lines 5–26) with:

```swift
public struct ShelfItem: Sendable, Identifiable {
    public let id: UUID
    public let originalURL: URL
    public let shelfURL: URL
    public let displayName: String
    public let addedAt: Date
    public let fileSize: Int64
    /// Name of the application the file was dragged from, if known.
    public let sourceAppName: String?
    /// Lowercased file extension (without the dot), if any.
    public let fileExtension: String?

    public init(
        id: UUID = UUID(),
        originalURL: URL,
        shelfURL: URL,
        displayName: String,
        addedAt: Date = Date(),
        fileSize: Int64,
        sourceAppName: String? = nil,
        fileExtension: String? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.shelfURL = shelfURL
        self.displayName = displayName
        self.addedAt = addedAt
        self.fileSize = fileSize
        self.sourceAppName = sourceAppName
        self.fileExtension = fileExtension
    }
}
```

- [ ] **Step 1.4: Populate `fileExtension` inside `storeFile`**

In `FileShelfManager.swift` replace the last `return ShelfItem(...)` block (lines 220–226) with:

```swift
        let ext = sourceURL.pathExtension.lowercased()
        return ShelfItem(
            id: itemID,
            originalURL: sourceURL,
            shelfURL: destURL,
            displayName: fileName,
            fileSize: fileSize,
            sourceAppName: nil,
            fileExtension: ext.isEmpty ? nil : ext
        )
```

- [ ] **Step 1.5: Add a `sourceAppName`-aware `addFiles` overload**

Still in `FileShelfManager.swift`, directly below the existing `addFiles(from:)` method, add:

```swift
    /// Add files and tag them with a source application name.
    /// Used when the drop pasteboard carries `com.apple.pasteboard.source-app-bundle-identifier`.
    @discardableResult
    public func addFiles(from urls: [URL], sourceAppName: String?) -> [ShelfItem] {
        let added = addFiles(from: urls)
        guard let sourceAppName, !added.isEmpty else { return added }
        let taggedIDs = Set(added.map { $0.id })
        items = items.map { existing in
            guard taggedIDs.contains(existing.id) else { return existing }
            return ShelfItem(
                id: existing.id,
                originalURL: existing.originalURL,
                shelfURL: existing.shelfURL,
                displayName: existing.displayName,
                addedAt: existing.addedAt,
                fileSize: existing.fileSize,
                sourceAppName: sourceAppName,
                fileExtension: existing.fileExtension
            )
        }
        // Return the updated items (post-tag) so the caller sees the app name.
        return items.filter { taggedIDs.contains($0.id) }
    }
```

- [ ] **Step 1.6: Run the new tests and ensure they pass**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
swift test --filter "FileShelfManagerTests" 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 1.7: Run the full test suite to check nothing else broke**

```bash
swift test 2>&1 | tail -40
```

Expected: all existing tests still pass.

- [ ] **Step 1.8: Commit**

```bash
git add DropZone/Sources/DropZoneLib/FileShelfManager.swift DropZone/Tests/DropZoneTests/FileShelfManagerTests.swift
git commit -m "feat: add sourceAppName and fileExtension to ShelfItem"
```

---

## Task 2: Plumb source-app bundle ID through the drop path

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/DragDestinationView.swift`
- Modify: `DropZone/Tests/DropZoneTests/DragDestinationViewTests.swift` (create if missing; otherwise extend)

- [ ] **Step 2.1: Write failing test for source-app extraction helper**

Append (or create) `DropZone/Tests/DropZoneTests/DragDestinationViewTests.swift`:

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct DragDestinationViewTests {
    @Test @MainActor
    func sourceAppNameFromBundleIDIsNilWhenUnknown() {
        let name = DragDestinationView.sourceAppName(forBundleID: "com.example.doesnotexist.totally-fake")
        #expect(name == nil)
    }

    @Test @MainActor
    func sourceAppNameFromBundleIDResolvesFinder() {
        let name = DragDestinationView.sourceAppName(forBundleID: "com.apple.finder")
        #expect(name == "Finder")
    }

    @Test @MainActor
    func sourceAppBundleIDTypeConstantMatchesApplePasteboardType() {
        #expect(DragDestinationView.sourceAppBundleIDType.rawValue
                == "com.apple.pasteboard.source-app-bundle-identifier")
    }
}
```

- [ ] **Step 2.2: Run the test — expect compile failure**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
swift test --filter "DragDestinationViewTests" 2>&1 | tail -20
```

Expected: compile fails (unknown symbols).

- [ ] **Step 2.3: Add the helper and pasteboard-type constant**

In `DropZone/Sources/DropZoneLib/DragDestinationView.swift`, inside the `DragDestinationView` class (next to `acceptedTypes`), add:

```swift
    /// Apple's private pasteboard type that carries the source app's bundle identifier
    /// during drag-and-drop. Present for most AppKit-based drag sources (Finder, Safari, Preview…).
    public static let sourceAppBundleIDType =
        NSPasteboard.PasteboardType("com.apple.pasteboard.source-app-bundle-identifier")

    /// Resolve a bundle identifier to the app's display name via NSWorkspace + Bundle.
    /// Returns nil if the bundle ID is unknown or the Info.plist has no `CFBundleName`.
    public static func sourceAppName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
    }
```

- [ ] **Step 2.4: Use the helper during `performDragOperation`**

Replace the body of `performDragOperation(_:)` in `DragDestinationView.swift` with:

```swift
    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty, let manager = fileShelfManager else { return false }

        let bundleID = sender.draggingPasteboard.string(forType: Self.sourceAppBundleIDType)
        let appName = bundleID.flatMap(Self.sourceAppName(forBundleID:))
        let added = manager.addFiles(from: urls, sourceAppName: appName)

        setHighlighted(false)
        dragItemCount = 0

        if !added.isEmpty {
            onFilesDropped?(added.count)
            return true
        }
        return false
    }
```

- [ ] **Step 2.5: Run the new tests**

```bash
swift test --filter "DragDestinationViewTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 2.6: Run the full suite**

```bash
swift test 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 2.7: Commit**

```bash
git add DropZone/Sources/DropZoneLib/DragDestinationView.swift DropZone/Tests/DropZoneTests/DragDestinationViewTests.swift
git commit -m "feat: capture source-app bundle ID and resolve to display name on drop"
```

---

## Task 3: Add `preActivatedSize` + pre-activation rect to `NotchGeometry`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/NotchGeometry.swift`
- Modify: `DropZone/Tests/DropZoneTests/NotchGeometryTests.swift` (append)

- [ ] **Step 3.1: Write failing tests**

Append to `DropZone/Tests/DropZoneTests/NotchGeometryTests.swift`:

```swift
@Test
func preActivatedSizeIs380x60() {
    #expect(NotchGeometry.preActivatedSize == NSSize(width: 380, height: 60))
}

@Test
func shelfExpandedSizeIs600x360() {
    #expect(NotchGeometry.shelfExpandedSize == NSSize(width: 600, height: 360))
}

@Test
func preActivationRectIsActivationZoneOutsetBy8Px() {
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
    let activation = NSRect(x: 370, y: 708, width: 260, height: 102) // notch ± paddings
    let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)

    let pre = geo.preActivationRect
    #expect(pre.minX == activation.minX - 8)
    #expect(pre.minY == activation.minY - 8)
    #expect(pre.width == activation.width + 16)
    #expect(pre.height == activation.height + 16)
}

@Test
func panelOriginCentersPreActivatedBarUnderNotch() {
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
    let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
    let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)

    let origin = geo.panelOrigin(for: NotchGeometry.preActivatedSize)
    #expect(origin.x == notch.midX - NotchGeometry.preActivatedSize.width / 2)
    #expect(origin.y == notch.maxY - NotchGeometry.preActivatedSize.height)
}
```

- [ ] **Step 3.2: Run tests — they must fail**

```bash
swift test --filter "NotchGeometryTests" 2>&1 | tail -30
```

Expected: compile error (unknown `preActivatedSize`, `shelfExpandedSize`, `preActivationRect`).

- [ ] **Step 3.3: Add the new constants and the `preActivationRect` accessor**

In `DropZone/Sources/DropZoneLib/NotchGeometry.swift`, inside `NotchGeometry`, just below the existing `expandedSize` declaration, add:

```swift
    /// Narrow pre-activation bar displayed when the cursor enters the pre-activation zone.
    public static let preActivatedSize = NSSize(width: 380, height: 60)
    /// Full shelf panel size (list view / thumbnail view).
    public static let shelfExpandedSize = NSSize(width: 600, height: 360)
    /// Hysteresis outset (px) between the pre-activation rect and the activation zone.
    public static let preActivationOutset: CGFloat = 8
```

Then append at the end of the `NotchGeometry` type (before the closing `}`):

```swift
    /// The pre-activation rect = `activationZone` grown by `preActivationOutset` on every side.
    /// The drag enters pre-activation when the cursor crosses this outer rect; it exits only
    /// when the cursor leaves `activationZone` proper (providing hysteresis against flicker).
    public var preActivationRect: NSRect {
        activationZone.insetBy(dx: -Self.preActivationOutset, dy: -Self.preActivationOutset)
    }
```

- [ ] **Step 3.4: Run the tests**

```bash
swift test --filter "NotchGeometryTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 3.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/NotchGeometry.swift DropZone/Tests/DropZoneTests/NotchGeometryTests.swift
git commit -m "feat: add preActivatedSize, shelfExpandedSize, and preActivationRect to NotchGeometry"
```

---

## Task 4: Add new settings (`shelfViewMode`, `shelfPersistence`)

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/SettingsManager.swift`
- Modify: `DropZone/Tests/DropZoneTests/SettingsManagerTests.swift`

- [ ] **Step 4.1: Write failing tests for defaults and round-trip**

Append to `DropZone/Tests/DropZoneTests/SettingsManagerTests.swift`:

```swift
@Test @MainActor
func shelfViewModeDefaultsToList() {
    let defaults = UserDefaults(suiteName: "test.shelfViewMode.\(UUID())")!
    defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }
    let settings = SettingsManager(defaults: defaults)
    #expect(settings.shelfViewMode == .list)
}

@Test @MainActor
func shelfViewModeRoundTrip() {
    let defaults = UserDefaults(suiteName: "test.shelfViewMode.rt.\(UUID())")!
    let settings = SettingsManager(defaults: defaults)
    settings.shelfViewMode = .thumbnail
    #expect(settings.shelfViewMode == .thumbnail)
    settings.shelfViewMode = .list
    #expect(settings.shelfViewMode == .list)
}

@Test @MainActor
func shelfPersistenceDefaultsToPersistent() {
    let defaults = UserDefaults(suiteName: "test.shelfPersistence.\(UUID())")!
    let settings = SettingsManager(defaults: defaults)
    #expect(settings.shelfPersistence == .persistent)
}

@Test @MainActor
func shelfPersistenceRoundTrip() {
    let defaults = UserDefaults(suiteName: "test.shelfPersistence.rt.\(UUID())")!
    let settings = SettingsManager(defaults: defaults)
    settings.shelfPersistence = .autoDismiss
    #expect(settings.shelfPersistence == .autoDismiss)
    settings.shelfPersistence = .persistent
    #expect(settings.shelfPersistence == .persistent)
}
```

- [ ] **Step 4.2: Run tests — expect compile failure**

```bash
swift test --filter "SettingsManagerTests" 2>&1 | tail -20
```

Expected: compile error (unknown `shelfViewMode`, `ShelfViewMode`, `shelfPersistence`, `ShelfPersistence`).

- [ ] **Step 4.3: Add the enums and accessors**

In `DropZone/Sources/DropZoneLib/SettingsManager.swift`, add the new key strings inside `SettingsKey` (near the existing entries):

```swift
    static let shelfViewMode = "shelfViewMode"
    static let shelfPersistence = "shelfPersistence"
```

Add two public enums below `AnimationSpeed`:

```swift
public enum ShelfViewMode: Int, CaseIterable, Sendable {
    case list = 0
    case thumbnail = 1

    public var label: String {
        switch self {
        case .list: "List"
        case .thumbnail: "Thumbnails"
        }
    }
}

public enum ShelfPersistence: Int, CaseIterable, Sendable {
    case persistent = 0
    case autoDismiss = 1

    public var label: String {
        switch self {
        case .persistent: "Until I close it"
        case .autoDismiss: "Auto-hide after drop"
        }
    }
}
```

Register defaults — in `registerDefaults()`, add two entries to the dictionary:

```swift
            SettingsKey.shelfViewMode: ShelfViewMode.list.rawValue,
            SettingsKey.shelfPersistence: ShelfPersistence.persistent.rawValue,
```

Add the accessors inside the `SettingsManager` class (place them between `showOnAllDisplays` and the `// MARK: - Convenience` section):

```swift
    // MARK: - Shelf View Mode

    public var shelfViewMode: ShelfViewMode {
        get {
            let raw = defaults.integer(forKey: SettingsKey.shelfViewMode)
            return ShelfViewMode(rawValue: raw) ?? .list
        }
        set {
            defaults.set(newValue.rawValue, forKey: SettingsKey.shelfViewMode)
            notifyChanged()
        }
    }

    // MARK: - Shelf Persistence

    public var shelfPersistence: ShelfPersistence {
        get {
            let raw = defaults.integer(forKey: SettingsKey.shelfPersistence)
            return ShelfPersistence(rawValue: raw) ?? .persistent
        }
        set {
            defaults.set(newValue.rawValue, forKey: SettingsKey.shelfPersistence)
            notifyChanged()
        }
    }
```

- [ ] **Step 4.4: Run the tests**

```bash
swift test --filter "SettingsManagerTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 4.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/SettingsManager.swift DropZone/Tests/DropZoneTests/SettingsManagerTests.swift
git commit -m "feat: add shelfViewMode and shelfPersistence settings"
```

---

## Task 5: Add `.preActivated` state + `enterPreActivation`/`exitPreActivation` to `DropZonePanel`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/DropZonePanel.swift`
- Create: `DropZone/Tests/DropZoneTests/DropZonePanelPreActivationTests.swift`

- [ ] **Step 5.1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/DropZonePanelPreActivationTests.swift`:

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct DropZonePanelPreActivationTests {
    @MainActor
    private func panel() -> DropZonePanel {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
        let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
        let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)
        return DropZonePanel(geometry: geo)
    }

    @Test @MainActor
    func enterPreActivationFromListeningSetsStateAndFrame() {
        let p = panel()
        p.enterListening()
        p.enterPreActivation(primaryFileName: "foo.pdf", extraCount: 2, shelfCount: 5)
        #expect(p.panelState == .preActivated)
        #expect(p.frame.size == NotchGeometry.preActivatedSize)
    }

    @Test @MainActor
    func enterPreActivationFromHiddenIsIgnored() {
        let p = panel()
        p.enterPreActivation(primaryFileName: "foo.pdf", extraCount: 0, shelfCount: 0)
        #expect(p.panelState == .hidden)
    }

    @Test @MainActor
    func exitPreActivationReturnsToListening() {
        let p = panel()
        p.enterListening()
        p.enterPreActivation(primaryFileName: "foo.pdf", extraCount: 0, shelfCount: 0)
        p.exitPreActivation()
        #expect(p.panelState == .listening)
    }

    @Test @MainActor
    func expandFromPreActivatedKeepsWidthAndHeight() {
        let p = panel()
        p.enterListening()
        p.enterPreActivation(primaryFileName: "foo.pdf", extraCount: 0, shelfCount: 0)
        p.expand()
        #expect(p.panelState == .expanded)
        // Expanded now matches preActivatedSize so morph is a crossfade, not a resize.
        #expect(p.frame.size == NotchGeometry.preActivatedSize)
    }
}
```

- [ ] **Step 5.2: Run tests — expect compile failure**

```bash
swift test --filter "DropZonePanelPreActivationTests" 2>&1 | tail -20
```

Expected: compile error (unknown `.preActivated` case, unknown `enterPreActivation`/`exitPreActivation`).

- [ ] **Step 5.3: Add `.preActivated` to `PanelState`**

In `DropZone/Sources/DropZoneLib/DropZonePanel.swift`, extend the `PanelState` enum (lines 4–10):

```swift
public enum PanelState: Sendable {
    case hidden
    case listening
    case preActivated   // Drag entered the outer pre-activation rect (narrow bar visible)
    case expanded       // Drop zone visible, accepting drops
    case shelfExpanded  // Full shelf UI visible (list or thumbnail view)
    case collapsed      // Collapsing back after drag leaves without drop
}
```

- [ ] **Step 5.4: Widen the drop-zone `.expanded` frame to match the pre-activation bar**

Still in `DropZonePanel.swift`, replace the `NotchGeometry.expandedSize` reference inside `expand()` (line ~156) with `NotchGeometry.preActivatedSize` so the morph from pre-activation to drop-zone is a crossfade, not a resize. Concretely, change:

```swift
        let targetSize = NotchGeometry.expandedSize
```
to:
```swift
        let targetSize = NotchGeometry.preActivatedSize
```

Do the same substitution in `repositionForCurrentState()` inside the `.expanded` branch (line ~339).

> Note: We intentionally *keep* `NotchGeometry.expandedSize` around (it's public) so existing callers keep compiling; it's simply no longer used here.

- [ ] **Step 5.5: Reference the new `shelfExpandedSize` from `NotchGeometry`**

Remove the now-duplicate `DropZonePanel.shelfExpandedSize` (lines 143–144) and replace every use inside `DropZonePanel.swift` with `NotchGeometry.shelfExpandedSize`. Concretely: in `expandShelf()` (line ~183) and `repositionForCurrentState()` (line ~343), change `Self.shelfExpandedSize` to `NotchGeometry.shelfExpandedSize`.

- [ ] **Step 5.6: Add the pre-activation content host and state transitions**

Near the other subview declarations in `DropZonePanel.swift` (around the `fileShelfView` declaration), add a hosting view for the SwiftUI bar:

```swift
    // Pre-activation bar (SwiftUI). Hidden unless `panelState == .preActivated`
    // or crossfading into `.expanded`. Content updated via `enterPreActivation(...)`.
    public let preActivationBarHost = NSHostingView(rootView: PreActivationBarView.empty)
```

(Import SwiftUI at the top of the file: `import SwiftUI`.)

In `configureVisualContent()`, after the existing subview additions, add:

```swift
        preActivationBarHost.frame = contentView.bounds
        preActivationBarHost.autoresizingMask = [.width, .height]
        preActivationBarHost.isHidden = true
        contentView.addSubview(preActivationBarHost, positioned: .below, relativeTo: dragDestinationView)
```

Add two new public methods near the other state transitions (`expand()`, `collapse()`):

```swift
    /// Enter the pre-activated (narrow bar) state from `.listening`.
    /// `primaryFileName` is the first filename in the pasteboard, `extraCount` is the rest.
    public func enterPreActivation(primaryFileName: String?, extraCount: Int, shelfCount: Int) {
        guard panelState == .listening || panelState == .preActivated else { return }

        preActivationBarHost.rootView = PreActivationBarView(
            primaryFileName: primaryFileName,
            extraCount: max(0, extraCount),
            shelfCount: max(0, shelfCount)
        )
        preActivationBarHost.isHidden = false

        panelState = .preActivated

        let targetSize = NotchGeometry.preActivatedSize
        let targetOrigin = geometry.panelOrigin(for: targetSize)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)

        if !isVisible {
            alphaValue = 0
            setFrame(targetFrame.insetBy(dx: 15, dy: 6), display: false)
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration * 0.6
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }
    }

    /// Leave pre-activated state — drag has moved back outside the pre-activation rect
    /// without ever entering the drop zone.
    public func exitPreActivation() {
        guard panelState == .preActivated else { return }
        preActivationBarHost.isHidden = true
        panelState = .listening
        if isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.collapseDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.orderOut(nil)
                }
            }
        }
    }
```

Update the guard inside `expand()` so `.preActivated → .expanded` is a valid transition:

```swift
    public func expand() {
        guard panelState != .expanded else { return }
        // Hide the pre-activation bar if we're morphing from that state.
        preActivationBarHost.isHidden = true
        panelState = .expanded
```

(Keep the rest of the existing `expand()` body.)

- [ ] **Step 5.7: Create the SwiftUI `PreActivationBarView` stub so the file compiles**

Create `DropZone/Sources/DropZoneLib/PreActivationBarView.swift`:

```swift
import SwiftUI

/// Narrow bar shown while a drag hovers the pre-activation zone.
/// Final UI (icon + filename + shelf badge) lands in Task 7 — this stub just
/// shows the filename so `DropZonePanel` can host it now.
public struct PreActivationBarView: View {
    public let primaryFileName: String?
    public let extraCount: Int
    public let shelfCount: Int

    public static let empty = PreActivationBarView(primaryFileName: nil, extraCount: 0, shelfCount: 0)

    public init(primaryFileName: String?, extraCount: Int, shelfCount: Int) {
        self.primaryFileName = primaryFileName
        self.extraCount = extraCount
        self.shelfCount = shelfCount
    }

    public var body: some View {
        // Minimal placeholder; full design implemented in Task 7.
        Text(primaryFileName ?? "Dragging…")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5.8: Run the DropZonePanel tests**

```bash
swift test --filter "DropZonePanelPreActivationTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 5.9: Run the full suite**

```bash
swift test 2>&1 | tail -40
```

Expected: all existing tests still pass.

- [ ] **Step 5.10: Commit**

```bash
git add DropZone/Sources/DropZoneLib/DropZonePanel.swift \
        DropZone/Sources/DropZoneLib/PreActivationBarView.swift \
        DropZone/Tests/DropZoneTests/DropZonePanelPreActivationTests.swift
git commit -m "feat: add preActivated panel state with enter/exit transitions and SwiftUI bar host"
```

---

## Task 6: Pre-activation threshold in `GlobalDragMonitor`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/GlobalDragMonitor.swift`
- Modify: `DropZone/Tests/DropZoneTests/GlobalDragMonitorTests.swift` (append)

- [ ] **Step 6.1: Write failing tests**

Append to `DropZone/Tests/DropZoneTests/GlobalDragMonitorTests.swift`:

```swift
@Test @MainActor
func onPreActivationEnterFiresBeforeActivation() {
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
    let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
    let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)

    let monitor = GlobalDragMonitor(geometry: geo)
    monitor.allGeometries = [1: geo]

    var entered: (CGDirectDisplayID, [String])?
    var exited: CGDirectDisplayID?
    monitor.onPreActivationEntered = { id, names in entered = (id, names) }
    monitor.onPreActivationExited = { id in exited = id }

    // A point just inside the pre-activation rect but outside activation proper
    let pointInPre = NSPoint(x: activation.minX - 4, y: activation.minY - 4)
    monitor.processPointerForTesting(pointInPre, fileNames: ["a.pdf", "b.pdf"])
    #expect(entered?.0 == 1)
    #expect(entered?.1 == ["a.pdf", "b.pdf"])

    // Moving the cursor far away exits
    monitor.processPointerForTesting(NSPoint(x: 0, y: 0), fileNames: [])
    #expect(exited == 1)
}

@Test @MainActor
func onDragEnteredZoneStillFiresForActivationPoint() {
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
    let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
    let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)

    let monitor = GlobalDragMonitor(geometry: geo)
    monitor.allGeometries = [1: geo]

    var zoneEntered: CGDirectDisplayID?
    monitor.onDragEnteredZone = { id in zoneEntered = id }

    monitor.processPointerForTesting(NSPoint(x: activation.midX, y: activation.midY), fileNames: ["c.txt"])
    #expect(zoneEntered == 1)
}

@Test @MainActor
func fileNamesReadsFromSuppliedArray() {
    // Ensures the callback plumbs the filenames we pass through the test entry point.
    let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
    let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
    let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)
    let monitor = GlobalDragMonitor(geometry: geo)
    monitor.allGeometries = [9: geo]

    var captured: [String] = []
    monitor.onPreActivationEntered = { _, names in captured = names }
    monitor.processPointerForTesting(NSPoint(x: activation.minX - 2, y: activation.minY - 2),
                                     fileNames: ["only.jpg"])
    #expect(captured == ["only.jpg"])
}
```

- [ ] **Step 6.2: Run tests — expect compile failure**

```bash
swift test --filter "GlobalDragMonitorTests" 2>&1 | tail -20
```

Expected: compile error (unknown callbacks + test entry point).

- [ ] **Step 6.3: Add the new callbacks and hit-test helpers**

In `DropZone/Sources/DropZoneLib/GlobalDragMonitor.swift`, inside the `Callbacks` MARK, add:

```swift
    /// Fired when the drag cursor enters a screen's pre-activation rect
    /// (outer ring around the activation zone). Provides the display ID and the
    /// filenames currently on the drag pasteboard.
    public var onPreActivationEntered: (@MainActor (_ displayID: CGDirectDisplayID, _ fileNames: [String]) -> Void)?
    /// Fired when the cursor leaves the pre-activation rect without entering the activation zone.
    public var onPreActivationExited: (@MainActor (_ displayID: CGDirectDisplayID) -> Void)?
```

Below `isInsideZone`, add:

```swift
    /// Whether the cursor is currently inside the *pre*-activation rect (the outer ring).
    public private(set) var isInsidePreActivation: Bool = false
    /// The display ID of the screen whose pre-activation rect the cursor is in (nil if none).
    public private(set) var preActivationDisplayID: CGDirectDisplayID?
```

Add a helper for looking up the pre-activation rect per geometry (place with the other hit-testing helpers):

```swift
    /// Find which screen's *pre-activation* rect contains the point. Returns display ID or nil.
    private func preActivationDisplayIDForPoint(_ point: NSPoint) -> CGDirectDisplayID? {
        for (displayID, geo) in allGeometries {
            if geo.preActivationRect.contains(point) { return displayID }
        }
        return nil
    }

    /// Read filenames from the drag pasteboard (last-seen ordering).
    private func currentDragFileNames() -> [String] {
        let pb = NSPasteboard(name: .drag)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            return urls.map { $0.lastPathComponent }
        }
        return []
    }
```

- [ ] **Step 6.4: Extend `pollMousePosition` to drive the new callbacks**

Replace the body of `pollMousePosition()` in `GlobalDragMonitor.swift` with:

```swift
    private func pollMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let fileNames = currentDragFileNames()
        processPointerForTesting(mouseLocation, fileNames: fileNames)
    }

    /// Visible-to-tests entry point. Separates pure geometry/state logic from
    /// `NSEvent.mouseLocation`/pasteboard reads so we can test it deterministically.
    public func processPointerForTesting(_ point: NSPoint, fileNames: [String]) {
        // --- Pre-activation (outer) ring ---
        let preHitID = preActivationDisplayIDForPoint(point)
        if let hitID = preHitID {
            if !isInsidePreActivation || preActivationDisplayID != hitID {
                if isInsidePreActivation, let prev = preActivationDisplayID, prev != hitID {
                    onPreActivationExited?(prev)
                }
                isInsidePreActivation = true
                preActivationDisplayID = hitID
                onPreActivationEntered?(hitID, fileNames)
            }
        } else if isInsidePreActivation {
            if let prev = preActivationDisplayID { onPreActivationExited?(prev) }
            isInsidePreActivation = false
            preActivationDisplayID = nil
        }

        // --- Inner activation zone (existing behaviour, unchanged shape) ---
        let hitDisplayID = displayIDForPoint(point)
        if let hitID = hitDisplayID {
            if !isInsideZone || activeDisplayID != hitID {
                if isInsideZone, let prevID = activeDisplayID, prevID != hitID {
                    onDragExitedZone?(prevID)
                }
                isInsideZone = true
                activeDisplayID = hitID
                onDragEnteredZone?(hitID)
            }
        } else if isInsideZone {
            if let prevID = activeDisplayID {
                onDragExitedZone?(prevID)
            }
            isInsideZone = false
            activeDisplayID = nil
        }
    }
```

- [ ] **Step 6.5: Reset the new state inside `resetState()`**

Replace `resetState()` with:

```swift
    private func resetState() {
        isDragActive = false
        isInsideZone = false
        activeDisplayID = nil
        isInsidePreActivation = false
        preActivationDisplayID = nil
    }
```

- [ ] **Step 6.6: Run the tests**

```bash
swift test --filter "GlobalDragMonitorTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 6.7: Commit**

```bash
git add DropZone/Sources/DropZoneLib/GlobalDragMonitor.swift DropZone/Tests/DropZoneTests/GlobalDragMonitorTests.swift
git commit -m "feat: pre-activation threshold and filename plumbing in GlobalDragMonitor"
```

---

## Task 7: Implement the real `PreActivationBarView` UI

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/PreActivationBarView.swift`
- Create: `DropZone/Tests/DropZoneTests/PreActivationBarViewTests.swift`

- [ ] **Step 7.1: Write failing tests (pure-state tests — no view rendering needed)**

Create `DropZone/Tests/DropZoneTests/PreActivationBarViewTests.swift`:

```swift
import Testing
@testable import DropZoneLib

struct PreActivationBarViewTests {
    @Test
    func primaryFallbacksToDraggingWhenNil() {
        let view = PreActivationBarView(primaryFileName: nil, extraCount: 0, shelfCount: 0)
        #expect(view.displayTitle == "Dragging…")
    }

    @Test
    func extraCountZeroHidesOverflowLabel() {
        let view = PreActivationBarView(primaryFileName: "a.pdf", extraCount: 0, shelfCount: 3)
        #expect(view.overflowLabel == nil)
    }

    @Test
    func extraCountGreaterThanZeroShowsOverflowLabel() {
        let view = PreActivationBarView(primaryFileName: "a.pdf", extraCount: 4, shelfCount: 3)
        #expect(view.overflowLabel == "+4")
    }

    @Test
    func shelfCountZeroHidesBadge() {
        let view = PreActivationBarView(primaryFileName: "a.pdf", extraCount: 0, shelfCount: 0)
        #expect(view.badgeLabel == nil)
    }

    @Test
    func shelfCountOver99ClampsTo99Plus() {
        let view = PreActivationBarView(primaryFileName: "a.pdf", extraCount: 0, shelfCount: 150)
        #expect(view.badgeLabel == "99+")
    }

    @Test
    func longFileNameMiddleTruncatesAbove40Chars() {
        let long = String(repeating: "x", count: 50) + ".pdf"
        let view = PreActivationBarView(primaryFileName: long, extraCount: 0, shelfCount: 0)
        #expect(view.displayTitle.count <= 40)
        #expect(view.displayTitle.contains("…"))
    }
}
```

- [ ] **Step 7.2: Run tests — expect failures for unknown properties**

```bash
swift test --filter "PreActivationBarViewTests" 2>&1 | tail -30
```

Expected: compile error (unknown `displayTitle`, `overflowLabel`, `badgeLabel`).

- [ ] **Step 7.3: Replace the stub with the full `PreActivationBarView`**

Overwrite `DropZone/Sources/DropZoneLib/PreActivationBarView.swift` with:

```swift
import SwiftUI

/// Narrow bar (380×60) shown while a drag hovers the pre-activation zone.
public struct PreActivationBarView: View {
    public let primaryFileName: String?
    public let extraCount: Int
    public let shelfCount: Int

    public static let empty = PreActivationBarView(primaryFileName: nil, extraCount: 0, shelfCount: 0)

    public init(primaryFileName: String?, extraCount: Int, shelfCount: Int) {
        self.primaryFileName = primaryFileName
        self.extraCount = extraCount
        self.shelfCount = shelfCount
    }

    // MARK: - View-model accessors (used by tests)

    /// What to render as the primary title. Falls back to "Dragging…" when name is missing,
    /// and middle-truncates names longer than 40 characters.
    public var displayTitle: String {
        guard let name = primaryFileName, !name.isEmpty else { return "Dragging…" }
        let limit = 40
        if name.count <= limit { return name }
        let keep = (limit - 1) / 2
        let start = name.prefix(keep)
        let end = name.suffix(keep)
        return "\(start)…\(end)"
    }

    /// Overflow label ("+N") shown when extraCount > 0.
    public var overflowLabel: String? {
        extraCount > 0 ? "+\(extraCount)" : nil
    }

    /// Trailing shelf-count badge. Hidden when 0, clamped to "99+".
    public var badgeLabel: String? {
        guard shelfCount > 0 else { return nil }
        return shelfCount > 99 ? "99+" : "\(shelfCount)"
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)

            Text(displayTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let overflow = overflowLabel {
                Text(overflow)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }

            Spacer(minLength: 8)

            if let badge = badgeLabel {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 7.4: Run tests**

```bash
swift test --filter "PreActivationBarViewTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 7.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/PreActivationBarView.swift DropZone/Tests/DropZoneTests/PreActivationBarViewTests.swift
git commit -m "feat: implement PreActivationBarView UI with overflow and badge labels"
```

---

## Task 8: `ShelfListRowView` — list row with source-app / type / size tags

**Files:**
- Create: `DropZone/Sources/DropZoneLib/ShelfListRowView.swift`
- Create: `DropZone/Tests/DropZoneTests/ShelfListRowViewTests.swift`

- [ ] **Step 8.1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/ShelfListRowViewTests.swift`:

```swift
import Testing
import Foundation
@testable import DropZoneLib

struct ShelfListRowViewTests {
    private func item(
        name: String = "report.pdf",
        size: Int64 = 1_234_567,
        app: String? = "Finder",
        ext: String? = "pdf"
    ) -> ShelfItem {
        ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/\(name)"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/\(name)"),
            displayName: name,
            fileSize: size,
            sourceAppName: app,
            fileExtension: ext
        )
    }

    @Test
    func tagsIncludeAppTypeAndSizeWhenAllPresent() {
        let row = ShelfListRowView(item: item())
        #expect(row.tags == ["Finder", "PDF", "1.2 MB"])
    }

    @Test
    func missingSourceAppDropsAppTag() {
        let row = ShelfListRowView(item: item(app: nil))
        #expect(row.tags == ["PDF", "1.2 MB"])
    }

    @Test
    func missingFileExtensionDropsTypeTag() {
        let row = ShelfListRowView(item: item(ext: nil))
        #expect(row.tags == ["Finder", "1.2 MB"])
    }

    @Test
    func zeroSizeDropsSizeTag() {
        let row = ShelfListRowView(item: item(size: 0))
        #expect(row.tags == ["Finder", "PDF"])
    }

    @Test
    func formatsSmallSizesAsBytes() {
        let row = ShelfListRowView(item: item(size: 512))
        // Last tag is the size
        #expect(row.tags.last == "512 bytes")
    }
}
```

- [ ] **Step 8.2: Run tests — expect compile failure**

```bash
swift test --filter "ShelfListRowViewTests" 2>&1 | tail -20
```

Expected: unknown type.

- [ ] **Step 8.3: Create `ShelfListRowView`**

Create `DropZone/Sources/DropZoneLib/ShelfListRowView.swift`:

```swift
import SwiftUI

/// Single row in the shelf list view: icon + filename + capsule tags.
public struct ShelfListRowView: View {
    public let item: ShelfItem

    public init(item: ShelfItem) {
        self.item = item
    }

    /// Tag labels (source app, file type, formatted size), in order, with `nil`/empty entries dropped.
    public var tags: [String] {
        var result: [String] = []
        if let app = item.sourceAppName, !app.isEmpty { result.append(app) }
        if let ext = item.fileExtension, !ext.isEmpty { result.append(ext.uppercased()) }
        if item.fileSize > 0 { result.append(Self.formatSize(item.fileSize)) }
        return result
    }

    private static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(relativeAgeString(item.addedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private func relativeAgeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 8.4: Run the tests**

```bash
swift test --filter "ShelfListRowViewTests" 2>&1 | tail -30
```

Expected: all pass. (If `ByteCountFormatter` produces "1.2 MB" with a non-breaking space or different punctuation on your locale, update the first test to use the formatter's output — but on macOS 14 the default locale yields "1.2 MB".)

- [ ] **Step 8.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/ShelfListRowView.swift DropZone/Tests/DropZoneTests/ShelfListRowViewTests.swift
git commit -m "feat: ShelfListRowView with app/type/size tag logic"
```

---

## Task 9: `ShelfListView` — vertical scrolling list

**Files:**
- Create: `DropZone/Sources/DropZoneLib/ShelfListView.swift`
- Create: `DropZone/Tests/DropZoneTests/ShelfListViewTests.swift`

- [ ] **Step 9.1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/ShelfListViewTests.swift`:

```swift
import Testing
import Foundation
@testable import DropZoneLib

struct ShelfListViewTests {
    private func item(_ name: String, added: Date) -> ShelfItem {
        ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/\(name)"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/\(name)"),
            displayName: name,
            addedAt: added,
            fileSize: 100,
            sourceAppName: "Finder",
            fileExtension: "txt"
        )
    }

    @Test
    func emptyItemsMarksEmpty() {
        let view = ShelfListView(items: [], onRemove: { _ in })
        #expect(view.isEmpty)
        #expect(view.sortedItems.isEmpty)
    }

    @Test
    func itemsAreSortedNewestFirst() {
        let older = item("a.txt", added: Date(timeIntervalSince1970: 1_000))
        let newer = item("b.txt", added: Date(timeIntervalSince1970: 2_000))
        let view = ShelfListView(items: [older, newer], onRemove: { _ in })
        #expect(view.sortedItems.map(\.displayName) == ["b.txt", "a.txt"])
    }

    @Test
    func removeCallbackInvokedWithItemID() {
        let it = item("x.txt", added: Date())
        var removed: UUID?
        let view = ShelfListView(items: [it], onRemove: { id in removed = id })
        view.invokeRemove(it.id)
        #expect(removed == it.id)
    }
}
```

- [ ] **Step 9.2: Run tests — expect failure**

```bash
swift test --filter "ShelfListViewTests" 2>&1 | tail -20
```

Expected: compile fail (unknown type).

- [ ] **Step 9.3: Create `ShelfListView`**

Create `DropZone/Sources/DropZoneLib/ShelfListView.swift`:

```swift
import SwiftUI

/// Vertical scrolling list of `ShelfItem` rows. Inherits sizing from its container.
public struct ShelfListView: View {
    public let items: [ShelfItem]
    public let onRemove: (UUID) -> Void

    public init(items: [ShelfItem], onRemove: @escaping (UUID) -> Void) {
        self.items = items
        self.onRemove = onRemove
    }

    public var isEmpty: Bool { items.isEmpty }

    public var sortedItems: [ShelfItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }

    /// Test helper — invokes the remove callback for a given ID.
    public func invokeRemove(_ id: UUID) { onRemove(id) }

    public var body: some View {
        Group {
            if isEmpty {
                VStack {
                    Spacer()
                    Text("No files on the shelf")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedItems) { item in
                            ShelfListRowView(item: item)
                                .contextMenu {
                                    Button("Remove", role: .destructive) { onRemove(item.id) }
                                }
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 9.4: Run the tests**

```bash
swift test --filter "ShelfListViewTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 9.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/ShelfListView.swift DropZone/Tests/DropZoneTests/ShelfListViewTests.swift
git commit -m "feat: ShelfListView with newest-first sorting and remove callback"
```

---

## Task 10: `ShelfHeaderView` — view-toggle and minimize buttons

**Files:**
- Create: `DropZone/Sources/DropZoneLib/ShelfHeaderView.swift`
- Create: `DropZone/Tests/DropZoneTests/ShelfHeaderViewTests.swift`

- [ ] **Step 10.1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/ShelfHeaderViewTests.swift`:

```swift
import Testing
@testable import DropZoneLib

struct ShelfHeaderViewTests {
    @Test
    func titleIncludesItemCount() {
        let header = ShelfHeaderView(itemCount: 7, viewMode: .list, isDragging: false,
                                     onToggleView: {}, onMinimize: {})
        #expect(header.titleLabel == "DropZone · 7 items")
    }

    @Test
    func titleSingularItem() {
        let header = ShelfHeaderView(itemCount: 1, viewMode: .list, isDragging: false,
                                     onToggleView: {}, onMinimize: {})
        #expect(header.titleLabel == "DropZone · 1 item")
    }

    @Test
    func toggleButtonDisabledWhileDragging() {
        let header = ShelfHeaderView(itemCount: 3, viewMode: .list, isDragging: true,
                                     onToggleView: {}, onMinimize: {})
        #expect(header.toggleDisabled)
    }

    @Test
    func invokeToggleCallsHandler() {
        var called = false
        let header = ShelfHeaderView(itemCount: 3, viewMode: .list, isDragging: false,
                                     onToggleView: { called = true }, onMinimize: {})
        header.invokeToggle()
        #expect(called)
    }

    @Test
    func invokeMinimizeCallsHandler() {
        var called = false
        let header = ShelfHeaderView(itemCount: 3, viewMode: .list, isDragging: false,
                                     onToggleView: {}, onMinimize: { called = true })
        header.invokeMinimize()
        #expect(called)
    }
}
```

- [ ] **Step 10.2: Run tests — expect failure**

```bash
swift test --filter "ShelfHeaderViewTests" 2>&1 | tail -20
```

Expected: compile error.

- [ ] **Step 10.3: Create `ShelfHeaderView`**

Create `DropZone/Sources/DropZoneLib/ShelfHeaderView.swift`:

```swift
import SwiftUI

public struct ShelfHeaderView: View {
    public let itemCount: Int
    public let viewMode: ShelfViewMode
    public let isDragging: Bool
    public let onToggleView: () -> Void
    public let onMinimize: () -> Void

    public init(
        itemCount: Int,
        viewMode: ShelfViewMode,
        isDragging: Bool,
        onToggleView: @escaping () -> Void,
        onMinimize: @escaping () -> Void
    ) {
        self.itemCount = itemCount
        self.viewMode = viewMode
        self.isDragging = isDragging
        self.onToggleView = onToggleView
        self.onMinimize = onMinimize
    }

    public var titleLabel: String {
        let noun = itemCount == 1 ? "item" : "items"
        return "DropZone · \(itemCount) \(noun)"
    }

    public var toggleDisabled: Bool { isDragging }

    public func invokeToggle() { onToggleView() }
    public func invokeMinimize() { onMinimize() }

    public var body: some View {
        HStack {
            Text(titleLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(action: onToggleView) {
                Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(toggleDisabled)
            .opacity(toggleDisabled ? 0.4 : 1)

            Button(action: onMinimize) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}
```

- [ ] **Step 10.4: Run the tests**

```bash
swift test --filter "ShelfHeaderViewTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 10.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/ShelfHeaderView.swift DropZone/Tests/DropZoneTests/ShelfHeaderViewTests.swift
git commit -m "feat: ShelfHeaderView with view-toggle (disabled during drag) and minimize buttons"
```

---

## Task 11: Host the list view + header inside `DropZonePanel.shelfExpanded`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/DropZonePanel.swift`
- Create: `DropZone/Tests/DropZoneTests/DropZonePanelShelfHostingTests.swift`

- [ ] **Step 11.1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/DropZonePanelShelfHostingTests.swift`:

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct DropZonePanelShelfHostingTests {
    @MainActor
    private func panel() -> DropZonePanel {
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let notch = NSRect(x: 500, y: 868, width: 200, height: 32)
        let activation = NSRect(x: 470, y: 808, width: 260, height: 102)
        let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)
        return DropZonePanel(geometry: geo)
    }

    @Test @MainActor
    func expandShelfUsesShelfExpandedSize() {
        let p = panel()
        p.expandShelf()
        #expect(p.frame.size == NotchGeometry.shelfExpandedSize)
    }

    @Test @MainActor
    func shelfHostsAndHeaderAreAddedOnce() {
        let p = panel()
        p.expandShelf()
        // One NSHostingView for the header, one for the list mode, plus legacy AppKit FileShelfView.
        let hostCount = p.contentView?.subviews.filter { "\(type(of: $0))".contains("NSHostingView") }.count ?? 0
        #expect(hostCount >= 2)
    }

    @Test @MainActor
    func updateShelfDataUpdatesRootView() {
        let p = panel()
        p.expandShelf()
        let items: [ShelfItem] = [
            ShelfItem(originalURL: URL(fileURLWithPath: "/tmp/a.txt"),
                      shelfURL: URL(fileURLWithPath: "/tmp/shelf/a.txt"),
                      displayName: "a.txt", fileSize: 10)
        ]
        p.updateShelfData(items: items, viewMode: .list, isDragging: false)
        #expect(p.shelfListHost.rootView.items.count == 1)
    }
}
```

- [ ] **Step 11.2: Run tests — expect failure**

```bash
swift test --filter "DropZonePanelShelfHostingTests" 2>&1 | tail -20
```

Expected: unknown `shelfListHost`/`updateShelfData`.

- [ ] **Step 11.3: Add hosting views and update method to `DropZonePanel`**

In `DropZone/Sources/DropZoneLib/DropZonePanel.swift`, near the existing subview declarations:

```swift
    public let shelfHeaderHost = NSHostingView(rootView: ShelfHeaderView(
        itemCount: 0, viewMode: .list, isDragging: false,
        onToggleView: {}, onMinimize: {}
    ))
    public let shelfListHost = NSHostingView(rootView: ShelfListView(items: [], onRemove: { _ in }))
```

Inside `configureVisualContent()`, after the existing `fileShelfView` insertion, add the header on top and the list below, both hidden initially:

```swift
        shelfHeaderHost.frame = NSRect(x: 0, y: contentView.bounds.height - 36,
                                       width: contentView.bounds.width, height: 36)
        shelfHeaderHost.autoresizingMask = [.width, .minYMargin]
        shelfHeaderHost.isHidden = true
        contentView.addSubview(shelfHeaderHost, positioned: .below, relativeTo: dragDestinationView)

        shelfListHost.frame = NSRect(x: 0, y: 0,
                                     width: contentView.bounds.width,
                                     height: contentView.bounds.height - 36)
        shelfListHost.autoresizingMask = [.width, .height]
        shelfListHost.isHidden = true
        contentView.addSubview(shelfListHost, positioned: .below, relativeTo: dragDestinationView)
```

Add a new method on `DropZonePanel`:

```swift
    /// Push fresh shelf content into the list view + header. Called by AppDelegate whenever
    /// items/settings change and the panel is in `.shelfExpanded`.
    public func updateShelfData(
        items: [ShelfItem],
        viewMode: ShelfViewMode,
        isDragging: Bool,
        onToggleView: @escaping () -> Void = {},
        onMinimize: @escaping () -> Void = {},
        onRemove: @escaping (UUID) -> Void = { _ in }
    ) {
        shelfHeaderHost.rootView = ShelfHeaderView(
            itemCount: items.count,
            viewMode: viewMode,
            isDragging: isDragging,
            onToggleView: onToggleView,
            onMinimize: onMinimize
        )
        shelfListHost.rootView = ShelfListView(items: items, onRemove: onRemove)

        let showList = viewMode == .list
        shelfListHost.isHidden = !showList
        shelfHeaderHost.isHidden = false
        fileShelfView.isHidden = showList
    }
```

In `expandShelf()`, after `fileShelfView.isHidden = false` (line ~180), add:

```swift
        shelfHeaderHost.isHidden = false
```

In `collapse()`'s completion block, hide the new hosts:

```swift
                self?.shelfHeaderHost.isHidden = true
                self?.shelfListHost.isHidden = true
```

- [ ] **Step 11.4: Run the tests**

```bash
swift test --filter "DropZonePanelShelfHostingTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 11.5: Run the full suite**

```bash
swift test 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 11.6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/DropZonePanel.swift DropZone/Tests/DropZoneTests/DropZonePanelShelfHostingTests.swift
git commit -m "feat: host ShelfHeaderView and ShelfListView inside DropZonePanel"
```

---

## Task 12: Wire `AppDelegate` — pre-activation callbacks, persistence policy, view-toggle

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/AppDelegate.swift`
- Modify: `DropZone/Tests/DropZoneTests/AppDelegateTests.swift`

- [ ] **Step 12.1: Write failing tests for policy helper**

Append to `DropZone/Tests/DropZoneTests/AppDelegateTests.swift`:

```swift
@Test @MainActor
func autoDismissPolicyYieldsTimer() {
    let delegate = AppDelegate()
    let defaults = UserDefaults(suiteName: "test.autoDismiss.\(UUID())")!
    let settings = SettingsManager(defaults: defaults)
    settings.shelfPersistence = .autoDismiss
    #expect(delegate.shouldScheduleAutoDismiss(settings: settings) == true)
}

@Test @MainActor
func persistentPolicyHasNoTimer() {
    let delegate = AppDelegate()
    let defaults = UserDefaults(suiteName: "test.persistent.\(UUID())")!
    let settings = SettingsManager(defaults: defaults)
    settings.shelfPersistence = .persistent
    #expect(delegate.shouldScheduleAutoDismiss(settings: settings) == false)
}
```

- [ ] **Step 12.2: Run tests — expect failure**

```bash
swift test --filter "AppDelegateTests.autoDismissPolicyYieldsTimer|AppDelegateTests.persistentPolicyHasNoTimer" 2>&1 | tail -20
```

Expected: compile error (unknown `shouldScheduleAutoDismiss`).

- [ ] **Step 12.3: Add the policy helper + wire pre-activation and view-toggle in `AppDelegate`**

In `DropZone/Sources/DropZoneLib/AppDelegate.swift`, add the helper near the bottom of the class (inside `AppDelegate`):

```swift
    // MARK: - Policy helpers

    /// Whether a post-drop auto-dismiss timer should be scheduled for the current settings.
    public func shouldScheduleAutoDismiss(settings: SettingsManager) -> Bool {
        settings.shelfPersistence == .autoDismiss
    }
```

Inside `wireGlobalDragMonitor(_:shelfManager:)`, below the existing `monitor.onDragEnteredZone` block add:

```swift
        // When a drag enters the outer pre-activation ring, show the narrow bar on that screen.
        monitor.onPreActivationEntered = { [weak self, weak shelfManager] displayID, fileNames in
            guard let self, let panel = self.panels[displayID], let manager = shelfManager else { return }
            if panel.panelState == .listening || panel.panelState == .preActivated {
                panel.enterPreActivation(
                    primaryFileName: fileNames.first,
                    extraCount: max(0, fileNames.count - 1),
                    shelfCount: manager.items.count
                )
            }
        }

        monitor.onPreActivationExited = { [weak self] displayID in
            guard let self, let panel = self.panels[displayID] else { return }
            if panel.panelState == .preActivated {
                panel.exitPreActivation()
            }
        }
```

Update `createPanel(...)` to push shelf data whenever the shelf is shown. Replace the `onFilesDropped` closure with:

```swift
        panel.dragDestinationView.onFilesDropped = { [weak self, weak panel, weak shelfManager] count in
            panel?.playDropConfirmation {
                guard let self, let panel, let manager = shelfManager,
                      let settings = self.settingsManager else { return }
                panel.fileShelfView.animateAddItems(Array(manager.items.suffix(count)))
                panel.expandShelf()
                self.pushShelfDataToPanel(panel, displayID: displayID)

                // Auto-dismiss policy
                if self.shouldScheduleAutoDismiss(settings: settings) {
                    self.scheduleHideShelf(for: displayID, panel: panel)
                }
            }
        }
```

Replace `onMouseEntered` / `onMouseExited` closures on `panel` with:

```swift
        panel.onMouseEntered = { [weak self, weak panel, weak shelfManager] in
            guard let panel, let manager = shelfManager else { return }
            self?.cancelHideShelfTimer(for: displayID)
            if !manager.items.isEmpty && panel.panelState != .shelfExpanded {
                panel.fileShelfView.reload()
                panel.expandShelf()
                self?.pushShelfDataToPanel(panel, displayID: displayID)
            }
        }
        panel.onMouseExited = { [weak self, weak panel] in
            guard let self, let panel, let settings = self.settingsManager else { return }
            if panel.panelState == .shelfExpanded && settings.shelfPersistence == .autoDismiss {
                self.scheduleHideShelf(for: displayID, panel: panel)
            }
        }
```

Add a new helper near the bottom of `AppDelegate`:

```swift
    @MainActor
    private func pushShelfDataToPanel(_ panel: DropZonePanel, displayID: CGDirectDisplayID) {
        guard let shelf = fileShelfManager, let settings = settingsManager else { return }
        panel.updateShelfData(
            items: shelf.items,
            viewMode: settings.shelfViewMode,
            isDragging: false,
            onToggleView: { [weak self, weak panel] in
                guard let self, let panel, let s = self.settingsManager else { return }
                s.shelfViewMode = s.shelfViewMode == .list ? .thumbnail : .list
                self.pushShelfDataToPanel(panel, displayID: displayID)
            },
            onMinimize: { [weak panel] in
                panel?.collapse()
            },
            onRemove: { [weak shelf] id in
                shelf?.removeItem(id)
            }
        )
    }
```

In `settings.onSettingsChanged` at the end of `applicationDidFinishLaunching`, after the existing reconcile logic, add:

```swift
            // If the shelf is currently open, refresh it so view-mode/persistence changes apply immediately.
            if let self {
                for (id, panel) in self.panels where panel.panelState == .shelfExpanded {
                    self.pushShelfDataToPanel(panel, displayID: id)
                }
            }
```

- [ ] **Step 12.4: Run new tests**

```bash
swift test --filter "AppDelegateTests" 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 12.5: Run the full suite**

```bash
swift test 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 12.6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/AppDelegate.swift DropZone/Tests/DropZoneTests/AppDelegateTests.swift
git commit -m "feat: wire AppDelegate for pre-activation, persistence policy, view toggle"
```

---

## Task 13: Expose both new settings in `SettingsView`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/SettingsView.swift`

> This task is UI-only and has no unit test (SwiftUI form rendering is manual-verify). Keep edits surgical.

- [ ] **Step 13.1: Read the existing `SettingsView`**

```bash
sed -n '1,120p' DropZone/Sources/DropZoneLib/SettingsView.swift
```

Note the surrounding section structure so new controls match.

- [ ] **Step 13.2: Add two `@State` properties and init-sync them**

In `DropZone/Sources/DropZoneLib/SettingsView.swift`, add near the other `@State` declarations (around line 18):

```swift
    @State private var shelfViewMode: ShelfViewMode
    @State private var shelfPersistence: ShelfPersistence
```

And in the initializer (around line 28), add:

```swift
        _shelfViewMode = State(initialValue: settingsManager.shelfViewMode)
        _shelfPersistence = State(initialValue: settingsManager.shelfPersistence)
```

- [ ] **Step 13.3: Add two `Picker` controls inside the main `Form`**

Inside the existing `Form`, add a new `Section` (place after the max-shelf-items section):

```swift
                Section("Shelf") {
                    Picker("View", selection: $shelfViewMode) {
                        ForEach(ShelfViewMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: shelfViewMode) { _, newValue in
                        settingsManager.shelfViewMode = newValue
                    }

                    Picker("Stay expanded", selection: $shelfPersistence) {
                        ForEach(ShelfPersistence.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: shelfPersistence) { _, newValue in
                        settingsManager.shelfPersistence = newValue
                    }
                }
```

- [ ] **Step 13.4: Build and launch locally to sanity-check (manual)**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
swift build 2>&1 | tail -20
```

Expected: builds cleanly.

- [ ] **Step 13.5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/SettingsView.swift
git commit -m "feat: add shelfViewMode and shelfPersistence pickers to SettingsView"
```

---

## Task 14: Integration, docs, manual verification

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `DropZone/Info.plist`

> Remember: do **not** push the feature branch to `main`. CLAUDE.md requires no-fast-forward merge and annotated tag only after merge.

- [ ] **Step 14.1: Manual verification checklist (record results in commit body)**

Do each of these on a Mac with a notched screen:

1. Start app (`swift run` from `DropZone/` or open the built `.app`).
2. Drag a file from Finder toward the notch. Confirm the **380×60 pre-activation bar** appears just as the cursor crosses the outer ring.
3. Continue toward the notch. Confirm the bar morphs (content crossfade, no resize) into the drop zone.
4. Drop. Confirm the shelf expands to **600×360** with the list view (default).
5. Click the **view toggle** in the header — shelf switches to the legacy thumbnail strip and back.
6. Click the **minimize button** — shelf collapses to the badged notch-attached state.
7. With setting `Stay expanded = Until I close it` (default), confirm the shelf doesn't auto-dismiss after drop.
8. Change setting to `Auto-hide after drop`; drop again; confirm the shelf collapses after ~1.5 s.
9. Drag a file, back cursor out of the notch without dropping; confirm pre-activation bar fades out.
10. Drag a single file vs. multiple files; confirm the `+N` overflow label appears only when >1 item.

- [ ] **Step 14.2: Run the whole test suite one more time**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
swift test 2>&1 | tail -40
```

Expected: all pass.

- [ ] **Step 14.3: Update `CHANGELOG.md`**

Open `CHANGELOG.md` (repo root) and add at the top:

```markdown
## [v0.4.0] — 2026-04-17

### Added
- **Drag pre-activation bar.** A narrow 380×60 bar appears below the notch as soon as a drag enters the outer pre-activation zone, previewing the dragged filename (+N for multiples) and the current shelf count.
- **Shelf list view.** New 600×360 shelf panel with a vertical list of files, each row showing the source app, type, and size as capsule tags. The legacy thumbnail strip is preserved and selectable in Settings.
- **Shelf header with view toggle + minimize button** — switch between list and thumbnail in place, or collapse to the badged notch state.
- **New settings:** `Shelf view` (List / Thumbnails) and `Stay expanded` (Until I close it / Auto-hide after drop).

### Changed
- The drop-zone frame widened to 380×60 to match the pre-activation bar so the morph is a content crossfade, not a resize.
- `ShelfItem` gained `sourceAppName` (from pasteboard `com.apple.pasteboard.source-app-bundle-identifier`) and `fileExtension` fields.

(Plan: `docs/superpowers/plans/2026-04-17-drag-preactivation-and-shelf-list.md` · Spec: `docs/superpowers/specs/2026-04-17-drag-preactivation-and-shelf-redesign-design.md`)
```

- [ ] **Step 14.4: Update the `README.md` version badge**

Open `README.md`, find the version badge (look for `v0.3.0`) and replace with `v0.4.0`.

- [ ] **Step 14.5: Update `DropZone/Info.plist`**

Bump `CFBundleShortVersionString` and `CFBundleVersion` to `0.4.0`.

- [ ] **Step 14.6: Commit the docs/version updates**

```bash
git add CHANGELOG.md README.md DropZone/Info.plist
git commit -m "docs: changelog and version bump for v0.4.0 pre-activation + shelf list"
```

- [ ] **Step 14.7: Merge prep — rebase onto `main`**

```bash
git fetch origin
git rebase origin/main
# resolve any conflicts; re-run swift test until green
swift test 2>&1 | tail -40
```

- [ ] **Step 14.8: Merge into `main` with `--no-ff` (per CLAUDE.md)**

```bash
git checkout main
git merge --no-ff plan-6-preactivation-and-shelf-list -m "Merge plan-6: drag pre-activation bar and shelf list redesign"
```

- [ ] **Step 14.9: Tag and push the release**

```bash
git tag -a v0.4.0 -m "v0.4.0: drag pre-activation bar and shelf list view"
git push origin main
git push origin v0.4.0
```

CI (`.github/workflows/release.yml`) builds the universal `.app` and publishes the release zip.

- [ ] **Step 14.10: Delete the merged feature branch**

```bash
git branch -d plan-6-preactivation-and-shelf-list
git push origin --delete plan-6-preactivation-and-shelf-list
```

---

## Appendix — spec coverage matrix

| Spec section / requirement | Task(s) |
|---|---|
| `.preActivated` state added to `PanelState` | 5 |
| 380×60 pre-activation bar size | 3, 5 |
| Hysteresis outset (+8 px, exits on inner rect) | 3, 6 |
| Pre-activation bar shows primary filename + `+N` + shelf badge | 7 |
| Drop-zone frame widened to 380×60 (crossfade, no resize) | 5 |
| `shelfExpandedSize = 600×360` | 3, 5 |
| `ShelfListView` with newest-first sort + empty state | 9 |
| `ShelfListRowView` with icon / filename / app·type·size tags | 8 |
| `ShelfHeaderView` with view-toggle (disabled on drag) + minimize | 10 |
| `SettingsManager.shelfViewMode` / `shelfPersistence` + defaults | 4 |
| Settings UI surface | 13 |
| `ShelfItem.sourceAppName` / `fileExtension` | 1 |
| Source-app bundle ID pasteboard plumbing | 2 |
| `GlobalDragMonitor` pre-activation threshold + filename plumbing | 6 |
| AppDelegate wiring: pre-activation + view-toggle + persistence | 12 |
| Pre-activation from `.hidden` rejected | 5 |
| `FileShelfManager` legacy decode path | 1 (default-nil init) |
| Tests under `DropZone/Tests/DropZoneTests/` using Swift Testing | every task |
| CHANGELOG / README / Info.plist version bump | 14 |
| Branching + merge checklist + SemVer MINOR tag | 0, 14 |
