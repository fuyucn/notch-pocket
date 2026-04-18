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
