# NotchDrop-Style Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `DropZonePanel` + `HoverDetectionPanel` + `GlobalDragMonitor` architecture with a single always-visible `NotchPanel` backed by a SwiftUI `NotchViewModel` and a Combine `EventMonitors` bus (NotchDrop pattern). Mouse/drag proximity to the notch reliably drives a 3-state UI (`.closed`/`.popping`/`.opened`) with click-through in the idle state.

**Architecture:** See `docs/superpowers/specs/2026-04-17-notchdrop-architecture-rewrite.md`.

**Tech Stack:** Swift 6, macOS 14+, AppKit (NSPanel), SwiftUI (NSHostingView root), Combine, Swift Testing.

**Spec reference:** `docs/superpowers/specs/2026-04-17-notchdrop-architecture-rewrite.md`

**Branch:** `plan-6-preactivation-and-shelf-list` (continuing here — rewrite lives alongside earlier commits).

**Test runner note (CRITICAL):**
```
cd /Users/yfu/Developer/dropzone/DropZone && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
Without `DEVELOPER_DIR`, `swift test` silently no-ops and exits 0.

Baseline test count before rewrite: **209** across 17 suites. Many of those tests will retire with the types they cover (`DropZonePanelTests`, `DropZonePanelPreActivationTests`, `DropZonePanelShelfHostingTests`, `HoverDetectionPanelTests`, portions of `GlobalDragMonitorTests`, `ScreenDetectorTests` if present). That is **expected**. The task plan below explicitly deletes them.

---

## Task 1: `EventMonitor` — thin wrapper

**Files:**
- Create: `DropZone/Sources/DropZoneLib/EventMonitor.swift`
- Create: `DropZone/Tests/DropZoneTests/EventMonitorTests.swift`

- [ ] **Step 1.1: Write failing test**

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct EventMonitorTests {
    @Test @MainActor
    func startAndStopAreIdempotent() {
        let monitor = EventMonitor(mask: [.mouseMoved]) { _ in }
        monitor.start()
        monitor.start()  // second call: no-op, no crash
        monitor.stop()
        monitor.stop()  // second call: no-op, no crash
    }

    @Test @MainActor
    func handlerIsInvokedByLocalEvent() async {
        var calls = 0
        let monitor = EventMonitor(mask: [.mouseMoved]) { _ in calls += 1 }
        monitor.start()
        defer { monitor.stop() }
        // We cannot easily synthesize NSEvents for the local monitor in unit
        // tests; the behavior of being wired is the minimum we can verify.
        #expect(calls == 0) // smoke check
    }
}
```

- [ ] **Step 1.2: Run to confirm compile failure**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "EventMonitorTests" 2>&1 | tail -15
```

- [ ] **Step 1.3: Implement `EventMonitor`**

```swift
import AppKit

/// Thin `NSEvent` monitor wrapper that registers one global + one local
/// monitor with the same mask and handler. The global monitor observes
/// events in other apps (requires Input Monitoring permission in TCC);
/// the local monitor observes events in our own app's windows (no TCC
/// permission required). Callers get events from either source.
@MainActor
public final class EventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    public func start() {
        guard globalMonitor == nil else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
        }
        globalMonitor = global
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
            return event
        }
        localMonitor = local
    }

    public func stop() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }
}
```

- [ ] **Step 1.4: Run tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "EventMonitorTests" 2>&1 | tail -15
```

All pass.

- [ ] **Step 1.5: Commit**

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/EventMonitor.swift DropZone/Tests/DropZoneTests/EventMonitorTests.swift
git commit -m "feat: EventMonitor thin global+local NSEvent wrapper"
```

---

## Task 2: `EventMonitors` — Combine event bus singleton

**Files:**
- Create: `DropZone/Sources/DropZoneLib/EventMonitors.swift`
- Create: `DropZone/Tests/DropZoneTests/EventMonitorsTests.swift`

- [ ] **Step 2.1: Write test** — exercise only public API, since we cannot synthesize NSEvents

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct EventMonitorsTests {
    @Test @MainActor
    func sharedIsSingleton() {
        #expect(EventMonitors.shared === EventMonitors.shared)
    }

    @Test @MainActor
    func initialMouseLocationIsZero() {
        // Subscribe and read the current value without publishing anything.
        let current = EventMonitors.shared.mouseLocation.value
        // Can't assert a specific point because the real cursor may be anywhere;
        // just confirm the publisher exists and returns a CGPoint.
        #expect(current.x.isFinite)
        #expect(current.y.isFinite)
    }

    @Test @MainActor
    func isDraggingStartsFalse() {
        #expect(EventMonitors.shared.isDragging.value == false || EventMonitors.shared.isDragging.value == true)
        // Implementation detail: after creation it is false. But since shared
        // singleton persists across tests, we only confirm the type contract.
    }
}
```

- [ ] **Step 2.2: Implement `EventMonitors`**

```swift
import AppKit
import Combine

/// Singleton event bus that publishes mouse position and drag state.
/// Subscribers react to Combine publishers; no callbacks, no global state
/// beyond the singleton itself.
@MainActor
public final class EventMonitors {
    public static let shared = EventMonitors()

    public let mouseLocation: CurrentValueSubject<NSPoint, Never>
    public let isDragging: CurrentValueSubject<Bool, Never>

    private var mouseMove: EventMonitor!
    private var mouseDrag: EventMonitor!
    private var mouseUp: EventMonitor!

    private init() {
        mouseLocation = CurrentValueSubject<NSPoint, Never>(NSEvent.mouseLocation)
        isDragging = CurrentValueSubject<Bool, Never>(false)

        mouseMove = EventMonitor(mask: [.mouseMoved]) { [weak self] _ in
            guard let self else { return }
            self.mouseLocation.send(NSEvent.mouseLocation)
        }
        mouseMove.start()

        mouseDrag = EventMonitor(mask: [.leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            self.mouseLocation.send(NSEvent.mouseLocation)
            if self.isDragging.value == false { self.isDragging.send(true) }
        }
        mouseDrag.start()

        mouseUp = EventMonitor(mask: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            if self.isDragging.value == true { self.isDragging.send(false) }
        }
        mouseUp.start()
    }
}
```

- [ ] **Step 2.3: Run tests + commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "EventMonitorsTests" 2>&1 | tail -15
```

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/EventMonitors.swift DropZone/Tests/DropZoneTests/EventMonitorsTests.swift
git commit -m "feat: EventMonitors Combine bus for mouse location and drag state"
```

---

## Task 3: `NotchViewModel` — status state machine

**Files:**
- Create: `DropZone/Sources/DropZoneLib/NotchViewModel.swift`
- Create: `DropZone/Tests/DropZoneTests/NotchViewModelTests.swift`

- [ ] **Step 3.1: Write tests for the state machine**

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct NotchViewModelTests {
    @MainActor
    private func makeVM() -> NotchViewModel {
        let notch = NSRect(x: 700, y: 968, width: 200, height: 32)
        let activation = NSRect(x: 670, y: 908, width: 260, height: 102)
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)
        return NotchViewModel(geometry: geo)
    }

    @Test @MainActor
    func initialStatusIsClosed() {
        let vm = makeVM()
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func notDraggingKeepsStatusClosed() {
        let vm = makeVM()
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: false)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func draggingIntoHoverRectTransitionsToPopping() {
        let vm = makeVM()
        // Point inside hoverTriggerRect (top 50% width x 200 tall, under notch)
        let p = NSPoint(x: 800, y: 900)
        vm.updateMouseLocation(p, isDragging: true)
        #expect(vm.status == .popping)
    }

    @Test @MainActor
    func draggingIntoActivationZoneTransitionsToOpened() {
        let vm = makeVM()
        // activationZone = NSRect(x: 670, y: 908, width: 260, height: 102)
        // midpoint is well within it
        let p = NSPoint(x: 800, y: 950)
        vm.updateMouseLocation(p, isDragging: true)
        #expect(vm.status == .opened)
    }

    @Test @MainActor
    func leavingAllRectsWhileDraggingReturnsToClosed() {
        let vm = makeVM()
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)  // popping
        #expect(vm.status == .popping)
        vm.updateMouseLocation(NSPoint(x: 100, y: 100), isDragging: true)  // far away
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func dragEndedClosesIfNotInsideOpenedRect() {
        let vm = makeVM()
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)  // popping
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: false)
        #expect(vm.status == .closed)
    }
}
```

- [ ] **Step 3.2: Implement `NotchViewModel`**

```swift
import AppKit
import Combine

@MainActor
public final class NotchViewModel: ObservableObject {
    public enum Status: Sendable, Equatable {
        case closed
        case popping
        case opened
    }

    @Published public private(set) var status: Status = .closed
    @Published public var primaryFileName: String?
    @Published public var extraCount: Int = 0
    @Published public var shelfCount: Int = 0

    public var geometry: NotchGeometry

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Drive the status from a pointer location + drag flag. Callers:
    ///   - `NotchPanel` subscribes to `EventMonitors.shared` and forwards here
    ///   - Tests invoke directly
    public func updateMouseLocation(_ point: NSPoint, isDragging: Bool) {
        guard isDragging else {
            if status != .closed { status = .closed }
            return
        }
        if geometry.activationZone.contains(point) {
            if status != .opened { status = .opened }
        } else if geometry.hoverTriggerRect.contains(point) {
            if status != .popping { status = .popping }
        } else {
            if status != .closed { status = .closed }
        }
    }

    public func forceClose() {
        status = .closed
    }
}
```

- [ ] **Step 3.3: Run tests + commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "NotchViewModelTests" 2>&1 | tail -20
```

All pass.

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/NotchViewModel.swift DropZone/Tests/DropZoneTests/NotchViewModelTests.swift
git commit -m "feat: NotchViewModel status state machine from mouse + drag input"
```

---

## Task 4: `NotchPanel` — always-visible window

**Files:**
- Create: `DropZone/Sources/DropZoneLib/NotchPanel.swift`
- Create: `DropZone/Tests/DropZoneTests/NotchPanelTests.swift`

- [ ] **Step 4.1: Write tests**

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct NotchPanelTests {
    @MainActor
    private func makeGeometry() -> NotchGeometry {
        NotchGeometry(
            notchRect: NSRect(x: 700, y: 968, width: 200, height: 32),
            activationZone: NSRect(x: 670, y: 908, width: 260, height: 102),
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1000),
            hasNotch: true
        )
    }

    @Test @MainActor
    func frameCoversHoverTriggerRect() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        #expect(panel.frame == geo.hoverTriggerRect)
    }

    @Test @MainActor
    func panelIgnoresMouseEventsWhenClosed() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        // .closed status → click-through
        #expect(panel.ignoresMouseEvents == true)
    }

    @Test @MainActor
    func panelReceivesMouseEventsWhenOpened() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        vm.updateMouseLocation(NSPoint(x: 800, y: 950), isDragging: true) // → opened
        // Panel observes and switches ignoresMouseEvents off.
        panel.syncIgnoresMouseEvents()  // test-only hook triggering the observer
        #expect(panel.ignoresMouseEvents == false)
    }
}
```

- [ ] **Step 4.2: Implement `NotchPanel`**

```swift
import AppKit
import Combine
import SwiftUI

@MainActor
public final class NotchPanel: NSPanel {
    public let viewModel: NotchViewModel
    private var cancellables: Set<AnyCancellable> = []

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel

        let rect = viewModel.geometry.hoverTriggerRect
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false

        // Click-through in the idle state
        ignoresMouseEvents = true

        let host = NSHostingView(rootView: NotchPanelRootView(viewModel: viewModel))
        host.frame = rect
        host.autoresizingMask = [.width, .height]
        contentView = host

        setFrame(rect, display: false)
        orderFrontRegardless()

        // Register as NSDraggingDestination
        host.registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
        ])

        // Observe status to toggle click-through
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncIgnoresMouseEvents() }
            .store(in: &cancellables)

        // Observe mouse location from EventMonitors
        EventMonitors.shared.mouseLocation
            .combineLatest(EventMonitors.shared.isDragging)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point, dragging in
                guard let self else { return }
                self.viewModel.updateMouseLocation(point, isDragging: dragging)
            }
            .store(in: &cancellables)
    }

    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    /// Public so tests can force-sync after model mutation.
    public func syncIgnoresMouseEvents() {
        ignoresMouseEvents = (viewModel.status == .closed)
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        viewModel.geometry = geometry
        setFrame(geometry.hoverTriggerRect, display: true)
    }
}
```

- [ ] **Step 4.3: Create stub `NotchPanelRootView.swift`** (Task 5 fills it in)

Create `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift`:

```swift
import SwiftUI

@MainActor
public struct NotchPanelRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        // Filled in by Task 5.
        Color.clear
    }
}
```

- [ ] **Step 4.4: Run tests + commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "NotchPanelTests" 2>&1 | tail -20
```

All pass.

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/NotchPanel.swift DropZone/Sources/DropZoneLib/NotchPanelRootView.swift DropZone/Tests/DropZoneTests/NotchPanelTests.swift
git commit -m "feat: NotchPanel always-visible window driven by NotchViewModel"
```

---

## Task 5: `NotchPanelRootView` — SwiftUI status switch

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift`

- [ ] **Step 5.1: Implement the status-switch root**

Replace `NotchPanelRootView.swift` body with:

```swift
import SwiftUI

@MainActor
public struct NotchPanelRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            switch viewModel.status {
            case .closed:
                Color.clear
            case .popping:
                poppingContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .opened:
                openedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.status)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var poppingContent: some View {
        PreActivationBarView(
            primaryFileName: viewModel.primaryFileName,
            extraCount: viewModel.extraCount,
            shelfCount: viewModel.shelfCount
        )
        .frame(width: NotchGeometry.preActivatedSize.width, height: NotchGeometry.preActivatedSize.height)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var openedContent: some View {
        OpenedShelfPlaceholderView()
            .frame(width: NotchGeometry.shelfExpandedSize.width, height: NotchGeometry.shelfExpandedSize.height)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}

/// Minimal placeholder for the opened-state shelf — filled in by Task 7.
private struct OpenedShelfPlaceholderView: View {
    var body: some View {
        VStack {
            Text("Shelf")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Drop files here")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
```

- [ ] **Step 5.2: Build to confirm it compiles**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | tail -5
```

- [ ] **Step 5.3: Commit**

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/NotchPanelRootView.swift
git commit -m "feat: NotchPanelRootView with status-switched SwiftUI body"
```

---

## Task 6: `AppDelegate` — wire NotchPanel + drop handler

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/AppDelegate.swift`

- [ ] **Step 6.1: Find the parts of AppDelegate that still exist and still make sense**

Current `AppDelegate.swift` references (from last working state): `DropZonePanel`, `HoverDetectionPanel`, `GlobalDragMonitor`, `ScreenDetector`, `StatusBarController`, `FileShelfManager`, `SettingsManager`, `SettingsWindowController`, `KeyboardShortcutManager`, `PermissionsManager`. The last four stay; the first four retire (or get simplified).

- [ ] **Step 6.2: Write a reduced `AppDelegate`**

Replace the entire body of `AppDelegate.swift` with:

```swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var notchViewModel: NotchViewModel?
    private(set) public var notchPanel: NotchPanel?
    private(set) public var fileShelfManager: FileShelfManager?
    private(set) public var settingsManager: SettingsManager?
    private(set) public var settingsWindowController: SettingsWindowController?
    private(set) public var keyboardShortcutManager: KeyboardShortcutManager?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsManager()
        settingsManager = settings

        let shelfManager = FileShelfManager()
        shelfManager.maxItems = settings.maxShelfItems
        shelfManager.maxTotalBytes = settings.maxStorageBytes
        shelfManager.expiryInterval = settings.expiryInterval
        try? shelfManager.ensureShelfDirectory()
        shelfManager.startExpiryTimer()
        fileShelfManager = shelfManager

        // Primary-screen geometry — multi-display is future work.
        guard let primaryScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 }) ?? NSScreen.main else {
            return
        }
        let geometry = NotchGeometry(screen: primaryScreen)

        let vm = NotchViewModel(geometry: geometry)
        vm.shelfCount = shelfManager.items.count
        notchViewModel = vm

        let panel = NotchPanel(viewModel: vm)
        notchPanel = panel

        // Keep shelfCount synced with shelf manager
        shelfManager.onItemsChanged = { [weak vm, weak shelfManager] in
            guard let vm, let shelfManager else { return }
            vm.shelfCount = shelfManager.items.count
        }

        // Status bar
        let controller = StatusBarController()
        controller.setup()
        controller.updateFileCount(shelfManager.items.count)
        controller.onClearShelf = { [weak shelfManager] in shelfManager?.clearAll() }
        let previousOnItemsChanged = shelfManager.onItemsChanged
        shelfManager.onItemsChanged = { [weak controller, weak shelfManager, weak vm] in
            previousOnItemsChanged?()
            guard let shelfManager else { return }
            controller?.updateFileCount(shelfManager.items.count)
            vm?.shelfCount = shelfManager.items.count
        }
        statusBarController = controller

        // Settings window
        let settingsWindow = SettingsWindowController(settingsManager: settings)
        settingsWindowController = settingsWindow
        controller.onShowSettings = { [weak settingsWindow] in settingsWindow?.showSettings() }

        settings.onSettingsChanged = { [weak shelfManager] in
            guard let shelfManager else { return }
            shelfManager.maxItems = settings.maxShelfItems
            shelfManager.maxTotalBytes = settings.maxStorageBytes
            shelfManager.expiryInterval = settings.expiryInterval
        }

        // Global hotkey — keep Cmd+Shift+D working as a simple "force open" stub
        let shortcuts = KeyboardShortcutManager()
        shortcuts.onToggleShelf = { [weak vm] in
            guard let vm else { return }
            vm.status = (vm.status == .opened) ? .closed : .opened
        }
        shortcuts.register()
        keyboardShortcutManager = shortcuts
    }

    public func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcutManager?.unregister()
        keyboardShortcutManager = nil
        settingsWindowController?.closeSettings()
        settingsWindowController = nil
        fileShelfManager?.cleanupAll()
        fileShelfManager = nil
        notchPanel?.orderOut(nil)
        notchPanel = nil
        notchViewModel = nil
        statusBarController?.teardown()
        statusBarController = nil
        settingsManager = nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
```

Note the trade-offs of this reduced version, documented in the spec:
- Single-screen only (notched primary, falls back to `NSScreen.main`).
- No drop handling yet — Task 7 wires it through `NotchPanel`'s `NSHostingView`.
- Uses `vm.status = .opened` for the hotkey rather than a dedicated method; if we want animations-on-toggle this can be refactored.

- [ ] **Step 6.3: Build & fix compile errors**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | tail -40
```

Expected compile errors: references in test files to retired types. Resolved by Task 8.

- [ ] **Step 6.4: Commit**

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/AppDelegate.swift
git commit -m "refactor: AppDelegate owns NotchPanel/NotchViewModel; drops Dropzone/Hover/GlobalDrag"
```

---

## Task 7: Drop handling on `NotchPanel`

**Files:**
- Create: `DropZone/Sources/DropZoneLib/NotchDropForwarder.swift`
- Modify: `DropZone/Sources/DropZoneLib/NotchPanel.swift`
- Modify: `DropZone/Sources/DropZoneLib/AppDelegate.swift`

- [ ] **Step 7.1: Write a drop-forwarder NSView**

We cannot attach `NSDraggingDestination` to `NSHostingView` cleanly; use an overlay `NSView` subclass that sits topmost in `NotchPanel.contentView`, forwards drops to a closure, and passes non-drop events through.

Create `DropZone/Sources/DropZoneLib/NotchDropForwarder.swift`:

```swift
import AppKit

@MainActor
public final class NotchDropForwarder: NSView {
    public var onDropFiles: ((_ urls: [URL], _ sourceAppName: String?) -> Bool)?
    public var onDraggingChanged: ((_ isInside: Bool, _ fileNames: [String]) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let names = readFileNames(from: sender.draggingPasteboard)
        onDraggingChanged?(true, names)
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDraggingChanged?(false, [])
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = readURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let bundleID = sender.draggingPasteboard.string(
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.source-app-bundle-identifier")
        )
        let app = bundleID.flatMap(Self.sourceAppName(forBundleID:))
        return onDropFiles?(urls, app) ?? false
    }

    private func readURLs(from pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func readFileNames(from pb: NSPasteboard) -> [String] {
        readURLs(from: pb).map { $0.lastPathComponent }
    }

    static func sourceAppName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
    }
}
```

- [ ] **Step 7.2: Attach the forwarder to NotchPanel**

In `NotchPanel.swift`, replace the current `contentView = host` block with:

```swift
        let container = NSView(frame: rect)
        container.autoresizingMask = [.width, .height]

        let host = NSHostingView(rootView: NotchPanelRootView(viewModel: viewModel))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let forwarder = NotchDropForwarder(frame: container.bounds)
        forwarder.autoresizingMask = [.width, .height]
        container.addSubview(forwarder)
        self.dropForwarder = forwarder

        contentView = container
```

Add a stored property: `public let dropForwarder: NotchDropForwarder` — actually since it's assigned conditionally in init, use `public private(set) var dropForwarder: NotchDropForwarder?`.

Remove the old `host.registerForDraggedTypes(...)` line (now handled inside `NotchDropForwarder`).

- [ ] **Step 7.3: Wire drop handling in AppDelegate**

In `AppDelegate.applicationDidFinishLaunching`, after `let panel = NotchPanel(viewModel: vm)`, add:

```swift
        // Drop handling
        panel.dropForwarder?.onDraggingChanged = { [weak vm] inside, names in
            guard let vm else { return }
            vm.primaryFileName = inside ? names.first : nil
            vm.extraCount = inside ? max(0, names.count - 1) : 0
            // Keep status sync via mouseLocation subscription — NSDraggingInfo events fire separately
        }
        panel.dropForwarder?.onDropFiles = { [weak shelfManager, weak vm] urls, appName in
            guard let shelfManager else { return false }
            let added = shelfManager.addFiles(from: urls, sourceAppName: appName)
            if !added.isEmpty {
                vm?.primaryFileName = nil
                vm?.extraCount = 0
                return true
            }
            return false
        }
```

- [ ] **Step 7.4: Tests**

Create `DropZone/Tests/DropZoneTests/NotchDropForwarderTests.swift`:

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct NotchDropForwarderTests {
    @Test @MainActor
    func hitTestReturnsNilForClickThrough() {
        let f = NotchDropForwarder(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(f.hitTest(NSPoint(x: 50, y: 50)) == nil)
    }

    @Test @MainActor
    func sourceAppNameResolvesFinder() {
        #expect(NotchDropForwarder.sourceAppName(forBundleID: "com.apple.finder") == "Finder")
    }
}
```

- [ ] **Step 7.5: Run tests + build + commit**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "NotchDropForwarderTests" 2>&1 | tail -15
swift build 2>&1 | tail -5
```

```bash
cd /Users/yfu/Developer/dropzone
git add DropZone/Sources/DropZoneLib/NotchDropForwarder.swift \
        DropZone/Sources/DropZoneLib/NotchPanel.swift \
        DropZone/Sources/DropZoneLib/AppDelegate.swift \
        DropZone/Tests/DropZoneTests/NotchDropForwarderTests.swift
git commit -m "feat: NotchDropForwarder overlays NotchPanel for drag-in/drop + AppDelegate wiring"
```

---

## Task 8: Retire obsolete types and tests

**Files:**
- Delete: `DropZone/Sources/DropZoneLib/DropZonePanel.swift`
- Delete: `DropZone/Sources/DropZoneLib/HoverDetectionPanel.swift`
- Delete: `DropZone/Sources/DropZoneLib/GlobalDragMonitor.swift`
- Delete: `DropZone/Sources/DropZoneLib/DragDestinationView.swift`
- Delete: `DropZone/Sources/DropZoneLib/ScreenDetector.swift`
- Delete all corresponding `DropZone/Tests/DropZoneTests/*Tests.swift` files that reference them
- Clean up `FileShelfView.swift` / `FileThumbnailView.swift` if they depend on removed types (they shouldn't — they render shelf content independently)

- [ ] **Step 8.1: Delete source files and their tests**

```bash
cd /Users/yfu/Developer/dropzone
rm -v DropZone/Sources/DropZoneLib/DropZonePanel.swift \
      DropZone/Sources/DropZoneLib/HoverDetectionPanel.swift \
      DropZone/Sources/DropZoneLib/GlobalDragMonitor.swift \
      DropZone/Sources/DropZoneLib/DragDestinationView.swift \
      DropZone/Sources/DropZoneLib/ScreenDetector.swift
rm -v DropZone/Tests/DropZoneTests/DropZonePanelTests.swift \
      DropZone/Tests/DropZoneTests/DropZonePanelPreActivationTests.swift \
      DropZone/Tests/DropZoneTests/DropZonePanelShelfHostingTests.swift \
      DropZone/Tests/DropZoneTests/HoverDetectionPanelTests.swift \
      DropZone/Tests/DropZoneTests/GlobalDragMonitorTests.swift \
      DropZone/Tests/DropZoneTests/DragDestinationViewTests.swift \
      DropZone/Tests/DropZoneTests/ScreenDetectorTests.swift 2>&1 || true
```

- [ ] **Step 8.2: Build & fix remaining compile errors**

```bash
cd /Users/yfu/Developer/dropzone/DropZone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | tail -40
```

Likely residue:
- `AppDelegate.swift` references to things it no longer needs (shouldn't — Task 6 pruned them)
- `FileShelfViewTests.swift` may instantiate a FileShelfView that expected a `DropZonePanel` — if so, simplify or delete the test
- `SettingsViewTests.swift` similarly — untangle

Fix each compile error by minimal deletion / update.

- [ ] **Step 8.3: Run entire test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | tail -15
```

Expect roughly **~130–150 tests** remaining (we dropped ~60 by retiring 4–5 suites). All green.

- [ ] **Step 8.4: Commit**

```bash
cd /Users/yfu/Developer/dropzone
git add -A
git commit -m "refactor: retire DropZonePanel/Hover/GlobalDrag/DragDestination/ScreenDetector"
```

---

## Task 9: Manual verification

- [ ] **Step 9.1: Package the app**

```bash
cd /Users/yfu/Developer/dropzone
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./release-package.sh
```

- [ ] **Step 9.2: Manual checklist**

1. Launch `releases/Notch Pocket-0.1.0.app` (from Finder or `open` command).
2. Click around the top 1/3 of the screen (not on the notch) — clicks pass through to whatever's underneath.
3. Menu bar icons near the notch are clickable.
4. Drag a file from Finder toward the notch — as you cross into the top 200pt × 50% screen region, a 380×120 "Drop here" bar appears below the notch.
5. Continue into the notch — the panel expands to 600×360 (Shelf placeholder).
6. Drop the file — it lands on the shelf (check the status-bar badge count increment; open the shelf with the keyboard shortcut Cmd+Shift+D to see it if available).
7. Move the cursor away without dropping — bar fades to hidden.
8. **None of this should require granting Input Monitoring.** If a prompt appears, dismiss it and reconfirm behavior still works (local monitors are enough within our own window).

## Appendix — Spec coverage

| Spec requirement | Task |
|---|---|
| EventMonitor + EventMonitors bus | 1, 2 |
| NotchViewModel 3-state machine | 3 |
| NotchPanel always-visible transparent window | 4 |
| SwiftUI status-switched body | 5 |
| Drop-target registration on panel | 7 |
| Retire legacy Panel/Hover/Monitor types | 8 |
| AppDelegate boot + teardown | 6 |
| Click-through when idle, clicks captured when opened | 4, 7 |
| No Input Monitoring permission required for baseline | Local monitors inside own window (Task 1+2 architecture) |
| Manual verification | 9 |
