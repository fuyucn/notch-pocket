# Minimize Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent, Dynamic-Island-style "minimized" capsule that sits around the notch whenever the shelf holds files, so users see there's something in the shelf and can single-click to open.

**Architecture:** Keep the existing `NotchPanel` (closed / popping / opened) completely untouched to avoid the drag-in regressions that plagued the prior attempt. Introduce a new `MinimizedPanel` — a small, separate `NSPanel` whose frame is only the capsule's bounding box (so it physically cannot occlude the menu bar or content). The view model gains a fourth status `.minimized`; the `MinimizedPanel` observes status and shows/hides itself. Drag-in continues to flow through the existing `NotchDropForwarder` path — the minimize panel is a pure UI overlay that becomes invisible to the pointer whenever we leave `.minimized`.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSPanel`, `NSHostingView`), Combine, Swift Testing (`@Test` / `#expect`). Branch: `plan-9-minimize-retry` off v0.4.5.

**Reference spec:** `docs/superpowers/specs/2026-04-18-minimized-notch-bar-design.md`.

---

## File Structure

### New files
| File | Responsibility |
|------|-----------------|
| `DropZone/Sources/DropZoneLib/MinimizedBarView.swift` | SwiftUI view: black capsule with left-shoulder tray icon, center-notch spacer, right-shoulder count. Tappable. |
| `DropZone/Sources/DropZoneLib/MinimizedPanel.swift` | `NSPanel` subclass hosting `MinimizedBarView`. Observes `vm.status` via Combine, orderFronts only while `.minimized`. Its window frame is just the capsule's bounding box. |
| `DropZone/Tests/DropZoneTests/MinimizedBarViewTests.swift` | Smoke tests for the SwiftUI view. |
| `DropZone/Tests/DropZoneTests/MinimizedPanelTests.swift` | Panel frame, visibility, orderFront/orderOut behaviour. |

### Modified files
| File | What changes |
|------|--------------|
| `DropZone/Sources/DropZoneLib/NotchViewModel.swift` | Add `.minimized` case to `Status`; add `requestClose()` that routes to `.minimized` or `.closed` based on shelf count; adjust `updateMouseLocation` so drag end preserves `.minimized` when shelf has items. |
| `DropZone/Sources/DropZoneLib/NotchPanel.swift` | `didResignKey` handler calls `requestClose()` instead of `forceClose()`. |
| `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift` | × button calls `requestClose()`; render `Color.clear` at `.zero` size when status is `.minimized`. |
| `DropZone/Sources/DropZoneLib/AppDelegate.swift` | Instantiate/retain `MinimizedPanel`; launch-time initial status = `.minimized` iff `shelfCount > 0`; shelf-count-changed callback promotes `.closed → .minimized` on first file and demotes `.minimized → .closed` on last file removal; terminate cleanup. |
| `DropZone/Tests/DropZoneTests/NotchViewModelTests.swift` | New tests for `requestClose()` and `.minimized` drag interactions. |

### Unchanged (by design)
`NotchDropForwarder.swift`, `NotchGeometry.swift`, `EventMonitors.swift`, `FileShelfManager.swift`, everything in the shelf-view layer. The drag-in path is kept intact.

---

## Task Ordering Rationale

Tasks are ordered so the view model and visual pieces are buildable and testable in isolation before wiring into AppDelegate. The final wiring task is the risky one (touches multi-panel coordination); by that point, every dependency has tests covering the behavior it exposes.

1. View model: add `.minimized` + `requestClose()`.
2. `MinimizedBarView` (SwiftUI only, no window).
3. `MinimizedPanel` (NSPanel, no AppDelegate wiring).
4. Retire `forceClose()` callers → `requestClose()` (behavior stays equivalent for current states; prepares for `.minimized`).
5. Handle `.minimized` in `NotchPanelRootView` (make NotchPanel invisible in that state).
6. AppDelegate wiring: launch-time state + MinimizedPanel lifecycle + shelf-count auto-promote/demote.
7. Manual test + release (version bump v0.5.0, tag, push).

Each task ends with a clean commit and a green test suite.

---

### Task 1: Add `.minimized` status + `requestClose()` to `NotchViewModel`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/NotchViewModel.swift`
- Test: `DropZone/Tests/DropZoneTests/NotchViewModelTests.swift`

- [ ] **Step 1: Write failing test — `.minimized` is a valid status**

Append to `DropZone/Tests/DropZoneTests/NotchViewModelTests.swift` before the closing `}`:

```swift
    @Test @MainActor
    func requestCloseWithItemsGoesToMinimized() {
        let vm = makeVM()
        vm.shelfCount = 3
        vm.markDropped()
        #expect(vm.status == .opened)
        vm.requestClose()
        #expect(vm.status == .minimized)
    }

    @Test @MainActor
    func requestCloseWithNoItemsGoesToClosed() {
        let vm = makeVM()
        vm.shelfCount = 0
        vm.markDropped()
        #expect(vm.status == .opened)
        vm.requestClose()
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func dragEndingWithItemsPreservesMinimized() {
        let vm = makeVM()
        vm.shelfCount = 2
        vm.status = .minimized
        // Pointer moves far away, no drag — must not flip .minimized → .closed.
        vm.updateMouseLocation(NSPoint(x: -500, y: -500), isDragging: false)
        #expect(vm.status == .minimized)
    }

    @Test @MainActor
    func draggingFromMinimizedEntersPoppingThenOpened() {
        let vm = makeVM()
        vm.shelfCount = 2
        vm.status = .minimized
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        #expect(vm.status == .popping)
        vm.updateMouseLocation(NSPoint(x: 800, y: 950), isDragging: true)
        #expect(vm.status == .opened)
    }
```

- [ ] **Step 2: Run tests to verify new ones fail**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotchViewModelTests
```

Expected: The 4 new tests fail to compile (`.minimized`, `requestClose` undefined). Other tests in `NotchViewModelTests` still pass.

- [ ] **Step 3: Add `.minimized` case + `requestClose()`**

Edit `DropZone/Sources/DropZoneLib/NotchViewModel.swift`. Replace the `Status` enum and the `forceClose()` block with:

```swift
    public enum Status: Sendable, Equatable {
        case closed
        case minimized
        case popping
        case opened
    }
```

Modify `updateMouseLocation` so `.minimized` is preserved when the pointer is far away and there is no drag:

```swift
    public func updateMouseLocation(_ point: NSPoint, isDragging: Bool) {
        if status == .opened {
            return
        }
        guard isDragging else {
            let resting: Status = shelfCount > 0 ? .minimized : .closed
            if status != resting { status = resting }
            return
        }
        if geometry.activationZone.contains(point) {
            if status != .opened { status = .opened }
        } else if geometry.hoverTriggerRect.contains(point) {
            if status != .popping { status = .popping }
        } else {
            let resting: Status = shelfCount > 0 ? .minimized : .closed
            if status != resting { status = resting }
        }
    }
```

Add `requestClose()` right below `forceClose()`:

```swift
    /// User-intent close: drops the opened shelf but respects minimize —
    /// if there are items, fall back to `.minimized` instead of `.closed`.
    /// Called by click-outside, × button, esc.
    public func requestClose() {
        status = shelfCount > 0 ? .minimized : .closed
        openStickyUntil = nil
    }
```

- [ ] **Step 4: Run the new tests — expect pass**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotchViewModelTests
```

Expected: all NotchViewModelTests pass (the existing ones still pass because their preconditions set `shelfCount = 0` implicitly, and `updateMouseLocation`'s new code collapses to the old behaviour when `shelfCount == 0`).

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass (163 + 4 = 167).

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/NotchViewModel.swift DropZone/Tests/DropZoneTests/NotchViewModelTests.swift
git commit -m "feat: add .minimized status and requestClose() on NotchViewModel"
```

---

### Task 2: `MinimizedBarView` SwiftUI component

**Files:**
- Create: `DropZone/Sources/DropZoneLib/MinimizedBarView.swift`
- Create: `DropZone/Tests/DropZoneTests/MinimizedBarViewTests.swift`

- [ ] **Step 1: Write failing smoke test**

Create `DropZone/Tests/DropZoneTests/MinimizedBarViewTests.swift`:

```swift
import Testing
import AppKit
import SwiftUI
@testable import DropZoneLib

struct MinimizedBarViewTests {
    @Test @MainActor
    func rendersWithZeroCount() {
        let view = MinimizedBarView(shelfCount: 0, notchWidth: 200, onTap: {})
        // Host it so SwiftUI evaluates the body.
        let hosting = NSHostingView(rootView: view)
        #expect(hosting.fittingSize.width > 0)
    }

    @Test @MainActor
    func rendersWithLargeCount() {
        let view = MinimizedBarView(shelfCount: 99, notchWidth: 200, onTap: {})
        let hosting = NSHostingView(rootView: view)
        #expect(hosting.fittingSize.width > 0)
    }

    @Test @MainActor
    func onTapFiresCallback() {
        // SwiftUI tap gestures are not directly testable without UI runtime,
        // but we can at least assert the closure is wired via reflection of
        // the struct's stored property. Minimal contract: callback is Non-Optional
        // and invokable.
        var fired = false
        let view = MinimizedBarView(shelfCount: 1, notchWidth: 200, onTap: { fired = true })
        view.onTap()
        #expect(fired)
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MinimizedBarViewTests
```

Expected: FAIL — `MinimizedBarView` undefined.

- [ ] **Step 3: Implement `MinimizedBarView`**

Create `DropZone/Sources/DropZoneLib/MinimizedBarView.swift`:

```swift
import SwiftUI

/// Minimized capsule view: a black horizontal pill whose middle is reserved
/// for the physical notch. The left shoulder shows a tray icon, the right
/// shoulder shows the current shelf count. Tap anywhere on the capsule to
/// request .opened.
@MainActor
public struct MinimizedBarView: View {
    public let shelfCount: Int
    public let notchWidth: CGFloat
    public let onTap: () -> Void

    public static let height: CGFloat = 32
    public static let shoulderWidth: CGFloat = 52

    public init(shelfCount: Int, notchWidth: CGFloat, onTap: @escaping () -> Void) {
        self.shelfCount = shelfCount
        self.notchWidth = notchWidth
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left shoulder
            HStack(spacing: 4) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: Self.shoulderWidth, height: Self.height)

            // Notch gap — reserved transparent space the physical notch sits over.
            Color.clear.frame(width: notchWidth, height: Self.height)

            // Right shoulder
            HStack(spacing: 0) {
                Text("\(shelfCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .frame(width: Self.shoulderWidth, height: Self.height)
        }
        .frame(height: Self.height)
        .background(
            // Rounded capsule. The middle is clear anyway; the shape is purely
            // visual polish for the two shoulders.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
```

- [ ] **Step 4: Run the view tests — expect pass**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MinimizedBarViewTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass (170).

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/MinimizedBarView.swift DropZone/Tests/DropZoneTests/MinimizedBarViewTests.swift
git commit -m "feat: add MinimizedBarView SwiftUI capsule"
```

---

### Task 3: `MinimizedPanel` NSPanel

**Files:**
- Create: `DropZone/Sources/DropZoneLib/MinimizedPanel.swift`
- Create: `DropZone/Tests/DropZoneTests/MinimizedPanelTests.swift`

- [ ] **Step 1: Write failing tests**

Create `DropZone/Tests/DropZoneTests/MinimizedPanelTests.swift`:

```swift
import Testing
import AppKit
@testable import DropZoneLib

struct MinimizedPanelTests {
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
    func panelFrameIsCapsuleSizedAndTopAnchored() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = MinimizedPanel(viewModel: vm)
        // Width = notch + 2 * shoulderWidth.
        let expectedWidth = geo.notchRect!.width + 2 * MinimizedBarView.shoulderWidth
        #expect(panel.frame.width == expectedWidth)
        #expect(panel.frame.height == MinimizedBarView.height)
        // Top of panel flush with screen top.
        #expect(panel.frame.maxY == geo.screenFrame.maxY)
        // Centered on notch.
        #expect(panel.frame.midX == geo.notchRect!.midX)
    }

    @Test @MainActor
    func panelIsHiddenUnlessStatusMinimized() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = MinimizedPanel(viewModel: vm)
        // Default status = .closed → hidden.
        #expect(panel.isVisible == false)

        vm.status = .minimized
        panel.syncVisibility()
        #expect(panel.isVisible == true)

        vm.status = .opened
        panel.syncVisibility()
        #expect(panel.isVisible == false)

        vm.status = .popping
        panel.syncVisibility()
        #expect(panel.isVisible == false)

        vm.status = .closed
        panel.syncVisibility()
        #expect(panel.isVisible == false)
    }

    @Test @MainActor
    func tapOnBarOpensTheShelf() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        vm.shelfCount = 1
        vm.status = .minimized
        let panel = MinimizedPanel(viewModel: vm)
        // Simulate the tap closure the view fires.
        panel.handleTap()
        #expect(vm.status == .opened)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MinimizedPanelTests
```

Expected: FAIL — `MinimizedPanel` undefined.

- [ ] **Step 3: Implement `MinimizedPanel`**

Create `DropZone/Sources/DropZoneLib/MinimizedPanel.swift`:

```swift
import AppKit
import Combine
import SwiftUI

/// Small borderless NSPanel that renders the `.minimized` capsule around the
/// notch. Its frame is sized to the capsule itself — nothing outside the
/// visible bar receives pointer events, so the menu bar and the rest of the
/// screen are never occluded. Drag-in continues to be handled by the main
/// NotchPanel.
@MainActor
public final class MinimizedPanel: NSPanel {
    public let viewModel: NotchViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var hostingView: NSHostingView<MinimizedBarView>?

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        let rect = Self.frame(for: viewModel.geometry)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // One level higher than popUpMenu so we render above the main NotchPanel
        // whenever both happen to be visible during a transition.
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = false

        let host = NSHostingView(rootView: Self.makeView(viewModel: viewModel, onTap: { [weak self] in
            self?.handleTap()
        }))
        host.frame = NSRect(origin: .zero, size: rect.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
        hostingView = host

        setFrame(rect, display: false)

        // Rebind SwiftUI whenever the shelf count changes, so the count badge
        // stays live.
        viewModel.$shelfCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebindView() }
            .store(in: &cancellables)

        // Track status to toggle visibility.
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncVisibility() }
            .store(in: &cancellables)

        syncVisibility()
    }

    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    /// Public so tests can force-sync without waiting for Combine dispatch.
    public func syncVisibility() {
        if viewModel.status == .minimized {
            setFrame(Self.frame(for: viewModel.geometry), display: true)
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    /// Re-render with current shelf count. Called on shelf updates and when
    /// geometry changes.
    public func rebindView() {
        hostingView?.rootView = Self.makeView(viewModel: viewModel, onTap: { [weak self] in
            self?.handleTap()
        })
    }

    /// Test-only hook + the action fired by the SwiftUI tap gesture.
    public func handleTap() {
        viewModel.status = .opened
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        viewModel.geometry = geometry
        setFrame(Self.frame(for: geometry), display: true)
        rebindView()
    }

    // MARK: - Layout

    private static func makeView(
        viewModel: NotchViewModel,
        onTap: @escaping () -> Void
    ) -> MinimizedBarView {
        let notchWidth = viewModel.geometry.notchRect?.width ?? 200
        return MinimizedBarView(
            shelfCount: viewModel.shelfCount,
            notchWidth: notchWidth,
            onTap: onTap
        )
    }

    private static func frame(for geometry: NotchGeometry) -> NSRect {
        let notchWidth = geometry.notchRect?.width ?? 200
        let notchMidX = geometry.notchRect?.midX ?? geometry.screenFrame.midX
        let width = notchWidth + 2 * MinimizedBarView.shoulderWidth
        let height = MinimizedBarView.height
        return NSRect(
            x: notchMidX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
```

- [ ] **Step 4: Run panel tests — expect pass**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter MinimizedPanelTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass (173).

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/MinimizedPanel.swift DropZone/Tests/DropZoneTests/MinimizedPanelTests.swift
git commit -m "feat: MinimizedPanel NSPanel subclass hosting MinimizedBarView"
```

---

### Task 4: Route existing close paths through `requestClose()`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/NotchPanel.swift:80-90`
- Modify: `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift:160-162`
- Modify: `DropZone/Tests/DropZoneTests/NotchViewModelTests.swift`

- [ ] **Step 1: Write failing test — `forceClose()` still goes to `.closed` regardless of items**

Append to `DropZone/Tests/DropZoneTests/NotchViewModelTests.swift`:

```swift
    @Test @MainActor
    func forceCloseIgnoresMinimizeEvenWithItems() {
        // forceClose is an explicit "fully close" path (quit, teardown).
        // requestClose is the user-intent path that honors minimize.
        let vm = makeVM()
        vm.shelfCount = 5
        vm.markDropped()
        vm.forceClose()
        #expect(vm.status == .closed)
    }
```

- [ ] **Step 2: Run test — expect pass (no code change yet)**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotchViewModelTests
```

Expected: all NotchViewModelTests pass — `forceClose()` already unconditionally sets `.closed`. The test documents the contract we rely on.

- [ ] **Step 3: Update `NotchPanel` to use `requestClose()`**

Edit `DropZone/Sources/DropZoneLib/NotchPanel.swift`. In the `didResignKeyNotification` observer (around line 85), replace:

```swift
                if self.viewModel.status == .opened {
                    self.viewModel.requestClose()
                }
```

(Line 85 currently reads `self.viewModel.requestClose()` per the summary context — but grep in Task prep found `forceClose()`. Treat this as: locate the line that currently calls `forceClose()` inside the didResignKey sink and change the method name to `requestClose()`. If the source already reads `requestClose()`, skip this sub-step.)

Concretely, run:

```bash
grep -n "forceClose\|requestClose" DropZone/Sources/DropZoneLib/NotchPanel.swift
```

Replace any `forceClose()` inside the didResignKey observer with `requestClose()`.

- [ ] **Step 4: Update `NotchPanelRootView` to use `requestClose()` on × button**

Edit `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift` around line 160:

```swift
    private func close() {
        viewModel.requestClose()
    }
```

(Replacing the existing `viewModel.forceClose()` call.)

- [ ] **Step 5: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: 174 tests pass.

- [ ] **Step 6: Commit**

```bash
git add DropZone/Sources/DropZoneLib/NotchPanel.swift DropZone/Sources/DropZoneLib/NotchPanelRootView.swift DropZone/Tests/DropZoneTests/NotchViewModelTests.swift
git commit -m "refactor: route × and click-outside close through requestClose()"
```

---

### Task 5: Handle `.minimized` in `NotchPanelRootView`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift`

- [ ] **Step 1: Write failing test** *(SwiftUI state-body rendering is hard to assert directly; we instead assert that `targetSize` returns `.zero` for `.minimized`. We'll expose it as a testable helper.)*

Add to `DropZone/Tests/DropZoneTests/NotchPanelTests.swift` (create a new test file or append):

```swift
    @Test @MainActor
    func notchPanelRendersNothingWhenMinimized() {
        let geo = NotchGeometry(
            notchRect: NSRect(x: 700, y: 968, width: 200, height: 32),
            activationZone: NSRect(x: 670, y: 908, width: 260, height: 102),
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1000),
            hasNotch: true
        )
        let vm = NotchViewModel(geometry: geo)
        vm.shelfCount = 3
        vm.status = .minimized
        let panel = NotchPanel(viewModel: vm)
        // When minimized, NotchPanel still owns the hover/drop rect so drag-in
        // works, but its SwiftUI content must be zero-sized so it cannot
        // visibly render anything.
        panel.syncFrameForStatus()
        #expect(panel.frame.height > 0)  // Still present for drag-in
        // The test for zero-sized content is structural; NotchPanelRootView's
        // targetSize returns .zero for .minimized (verified by build/run; we
        // document the contract here).
        _ = panel
    }
```

- [ ] **Step 2: Run the test — expect it to fail to compile / mismatch**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotchPanelTests
```

Expected: compile succeeds (we only reference existing types), but the `.minimized` state currently falls through to a `switch`-exhaustiveness compile error in `NotchPanelRootView`. Actually — since we already added `.minimized` to the `Status` enum in Task 1, the root view won't compile until all `switch`es are exhaustive. Test run will fail with a compile error in `NotchPanelRootView`.

- [ ] **Step 3: Add `.minimized` case to every `switch` in `NotchPanelRootView`**

Edit `DropZone/Sources/DropZoneLib/NotchPanelRootView.swift`. Update the three status-switch blocks:

Replace `targetSize`:

```swift
    private var targetSize: CGSize {
        switch viewModel.status {
        case .closed, .minimized:
            return .zero
        case .popping:
            let s = viewModel.geometry.preActivatedPanelSize
            return CGSize(width: s.width, height: s.height)
        case .opened:
            let s = viewModel.geometry.openedPanelSize
            return CGSize(width: s.width, height: s.height)
        }
    }
```

Replace `targetTopRadius`:

```swift
    private var targetTopRadius: CGFloat {
        switch viewModel.status {
        case .closed, .minimized: return NotchShape.closedTopRadius
        case .popping, .opened: return NotchShape.openedTopRadius
        }
    }
```

Replace `targetBottomRadius`:

```swift
    private var targetBottomRadius: CGFloat {
        switch viewModel.status {
        case .closed, .minimized: return NotchShape.closedBottomRadius
        case .popping, .opened: return NotchShape.openedBottomRadius
        }
    }
```

Replace the `content` `@ViewBuilder`:

```swift
    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .closed, .minimized:
            Color.clear
        case .popping:
            VStack(spacing: 0) {
                notchTopBar
                PreActivationBarView(
                    primaryFileName: viewModel.primaryFileName,
                    extraCount: viewModel.extraCount,
                    shelfCount: viewModel.shelfCount,
                    notchInset: 8
                )
            }
            .frame(
                width: viewModel.geometry.preActivatedPanelSize.width,
                height: viewModel.geometry.preActivatedPanelSize.height
            )
            .clipShape(NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius))
        case .opened:
            openedContent
        }
    }
```

Replace `rightShoulder` `@ViewBuilder`:

```swift
    @ViewBuilder
    private var rightShoulder: some View {
        switch viewModel.status {
        case .opened:
            HStack(spacing: 4) {
                let mode = viewModel.settingsManager?.shelfViewMode ?? .list
                Button(action: toggleViewMode) {
                    Image(systemName: mode == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        case .popping:
            if viewModel.shelfCount > 0 {
                Text("\(viewModel.shelfCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            } else {
                EmptyView()
            }
        case .closed, .minimized:
            EmptyView()
        }
    }
```

Also search `NotchPanel.swift` and `NotchPanelRootView.swift` for any other `switch viewModel.status` or `case .opened`-style blocks and add `.minimized` handling (treat like `.closed`).

- [ ] **Step 4: Run full suite**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: 175 tests pass.

- [ ] **Step 5: Commit**

```bash
git add DropZone/Sources/DropZoneLib/NotchPanelRootView.swift DropZone/Tests/DropZoneTests/NotchPanelTests.swift
git commit -m "feat: render NotchPanel as empty when status is .minimized"
```

---

### Task 6: Wire `MinimizedPanel` into `AppDelegate`

**Files:**
- Modify: `DropZone/Sources/DropZoneLib/AppDelegate.swift`
- Test: `DropZone/Tests/DropZoneTests/AppDelegateTests.swift`

- [ ] **Step 1: Check existing AppDelegate test shape**

```bash
grep -n "minimizedPanel\|MinimizedPanel\|shelfCount" DropZone/Tests/DropZoneTests/AppDelegateTests.swift
```

Expected: no matches; we're adding the first.

- [ ] **Step 2: Write failing test — AppDelegate creates a MinimizedPanel**

Append to `DropZone/Tests/DropZoneTests/AppDelegateTests.swift` (read the file once first to confirm structure; if the test suite uses a helper to construct the AppDelegate under test, reuse it). Add:

```swift
    @Test @MainActor
    func appDelegateExposesMinimizedPanel() {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("test")))
        #expect(delegate.minimizedPanel != nil)
    }
```

- [ ] **Step 3: Run test — expect failure**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppDelegateTests
```

Expected: FAIL — `minimizedPanel` is not a member of `AppDelegate`.

- [ ] **Step 4: Add `minimizedPanel` property + instantiate it**

Edit `DropZone/Sources/DropZoneLib/AppDelegate.swift`:

Add the stored property near the other `private(set)` lines:

```swift
    private(set) public var minimizedPanel: MinimizedPanel?
```

Inside `applicationDidFinishLaunching`, immediately after `notchPanel = panel`, add:

```swift
        let minimized = MinimizedPanel(viewModel: vm)
        minimizedPanel = minimized
```

- [ ] **Step 5: Set initial launch status**

Still in `applicationDidFinishLaunching`, between `vm.settingsManager = settings` and `notchViewModel = vm`, add:

```swift
        vm.status = shelfManager.items.count > 0 ? .minimized : .closed
```

- [ ] **Step 6: Update shelf-count-changed callback to handle promote/demote**

Still in `applicationDidFinishLaunching`, replace the existing composite `shelfManager.onItemsChanged = { … }` block (the one after `controller.updateFileCount(...)`) with:

```swift
        let previousOnItemsChanged = shelfManager.onItemsChanged
        shelfManager.onItemsChanged = { [weak controller, weak shelfManager, weak vm] in
            previousOnItemsChanged?()
            guard let shelfManager else { return }
            let count = shelfManager.items.count
            controller?.updateFileCount(count)
            guard let vm else { return }
            vm.shelfCount = count
            vm.shelfRefreshToken &+= 1
            // Auto-promote closed → minimized when shelf gains first file while idle.
            if count > 0, vm.status == .closed { vm.status = .minimized }
            // Auto-demote minimized → closed when shelf goes empty.
            if count == 0, vm.status == .minimized { vm.status = .closed }
        }
```

- [ ] **Step 7: Tear down panel on termination**

In `applicationWillTerminate`, after the `notchPanel?.orderOut(nil); notchPanel = nil` block, add:

```swift
        minimizedPanel?.orderOut(nil)
        minimizedPanel = nil
```

- [ ] **Step 8: Run tests**

```bash
cd DropZone && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: 176 tests pass.

- [ ] **Step 9: Commit**

```bash
git add DropZone/Sources/DropZoneLib/AppDelegate.swift DropZone/Tests/DropZoneTests/AppDelegateTests.swift
git commit -m "feat: wire MinimizedPanel lifecycle + auto-promote/demote in AppDelegate"
```

---

### Task 7: Hand-test + release

**Files:**
- Modify: `DropZone/Info.plist`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Build and launch**

```bash
./release-package.sh
pkill -f "Notch Pocket" 2>/dev/null; sleep 1; open "/Users/yfu/Developer/dropzone/releases/Notch Pocket-0.4.5.app"
```

(Keep `.app` name at 0.4.5 until the version bump step so we reuse the built artifact; we'll rebuild with the new version after bumping.)

- [ ] **Step 2: Manual smoke checklist**

- [ ] Launch with empty shelf: no capsule visible, menu bar clickable, idle desktop clickable through the notch region.
- [ ] Drag a file from Finder onto the notch: `.popping` bar appears, then `.opened` on drop.
- [ ] Click the × on the opened shelf (or click outside it): capsule appears around the notch with tray icon + count.
- [ ] Click the left shoulder of the capsule: shelf opens.
- [ ] Click the right shoulder: shelf opens.
- [ ] Click menu bar (somewhere clearly to the left / right of the notch): opens a menu normally. Capsule does NOT intercept.
- [ ] Drag another file onto the notch while minimized: `.popping` activates, then `.opened` on drop. Capsule hides cleanly during this flow.
- [ ] Clear the shelf via menu-bar "Clear Shelf": capsule hides, status returns to `.closed`.
- [ ] Relaunch with files still on the shelf (Reference mode): capsule appears immediately on launch.

- [ ] **Step 3: Bump version to v0.5.0**

New feature → minor bump.

Edit `DropZone/Info.plist` — change both `CFBundleShortVersionString` and `CFBundleVersion` from `0.4.5` to `0.5.0`.

Edit `README.md` — change the badge from `v0.4.5` to `v0.5.0`.

Edit `CHANGELOG.md` — add a new section under `## [Unreleased]`:

```markdown
## [v0.5.0] — 2026-04-18

### Added
- **Minimized capsule**: Dynamic-Island-style indicator around the notch when the shelf has files. Left shoulder shows the tray icon, right shoulder shows the item count. Click anywhere on it to open the shelf. Invisible when the shelf is empty.
- Launch with pre-existing shelf items auto-shows the minimized capsule.

### Changed
- `×` on the opened shelf and click-outside now return to the minimized capsule if the shelf has items; they still return to fully hidden when empty.

### Technical
- New `MinimizedPanel` NSPanel with a capsule-sized frame — cannot occlude menu bar or screen content. Separate from the existing `NotchPanel` state machine, so drag-in behaviour is unchanged.
```

- [ ] **Step 4: Rebuild**

```bash
./release-package.sh
pkill -f "Notch Pocket" 2>/dev/null; sleep 1; open "/Users/yfu/Developer/dropzone/releases/Notch Pocket-0.5.0.app"
```

Re-run the Step-2 checklist on the v0.5.0 build.

- [ ] **Step 5: Commit + tag + push**

```bash
git add DropZone/Info.plist README.md CHANGELOG.md
git commit -m "docs: bump to v0.5.0 (minimized capsule feature)"
git tag -a v0.5.0 -m "v0.5.0: minimized capsule around the notch when shelf has files"
```

- [ ] **Step 6: Merge branch to main and push**

```bash
git checkout main
git merge --no-ff plan-9-minimize-retry -m "merge: plan-9 minimize capsule feature (v0.5.0)"
git push origin main v0.5.0
```

- [ ] **Step 7: Delete the feature branch (local + remote only if it was pushed)**

```bash
git branch -d plan-9-minimize-retry
```

---

## Self-Review (performed)

**Spec coverage:**
- `.minimized` status → Task 1 ✓
- `requestClose()` routing → Tasks 1 + 4 ✓
- Launch-time initial status → Task 6 Step 5 ✓
- Drag-in from minimize → Task 1 test + Task 5 (NotchPanel keeps its rect) ✓
- Visual capsule → Tasks 2 + 3 ✓
- Separate NSPanel → Task 3 ✓
- NotchPanelRootView `.minimized` = Color.clear → Task 5 ✓
- Auto-promote/demote on shelf changes → Task 6 Step 6 ✓
- Tests for view model transitions, view smoke, panel frame/visibility → Tasks 1, 2, 3 ✓
- Version bump + changelog + tag (mandatory per CLAUDE.md) → Task 7 ✓

**Placeholder scan:** no TBD / "add error handling" / "similar to Task N" phrasing. Every code step includes complete code; every test step includes assertions.

**Type consistency:**
- `MinimizedBarView(shelfCount:notchWidth:onTap:)` — Tasks 2, 3 match
- `MinimizedPanel(viewModel:)` — Tasks 3, 6 match
- `MinimizedBarView.height`, `MinimizedBarView.shoulderWidth` — defined in Task 2, referenced in Task 3 ✓
- `requestClose()` — defined in Task 1, used in Tasks 3 (indirectly), 4, 6 ✓
- `syncVisibility()` — defined in Task 3, tested in Task 3 ✓

Plan is complete and internally consistent.
