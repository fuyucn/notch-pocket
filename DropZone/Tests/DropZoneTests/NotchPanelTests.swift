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
    func closedPanelFrameIsSmallTopAnchoredDragTarget() {
        // In .closed the panel shrinks to a small rect under the notch so
        // it doesn't block clicks, but stays large enough for AppKit to
        // deliver draggingEntered when a file drag passes over.
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        #expect(panel.frame.maxY == geo.screenFrame.maxY)
        #expect(panel.frame.width < geo.hoverTriggerRect.width)
        #expect(panel.frame.height < geo.openedPanelSize.height)
        #expect(panel.frame.width > 0)
        #expect(panel.frame.height > 0)
    }

    @Test @MainActor
    func panelDoesNotIgnoreMouseEventsWhenClosed() {
        // Panel cannot ignoreMouseEvents because AppKit would then skip
        // NSDraggingDestination dispatch. Click-through is instead achieved
        // by giving .closed a tiny frame.
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        #expect(panel.ignoresMouseEvents == false)
    }

    @Test @MainActor
    func panelReceivesMouseEventsWhenOpened() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        vm.updateMouseLocation(NSPoint(x: 800, y: 950), isDragging: true)
        panel.syncIgnoresMouseEvents()
        #expect(panel.ignoresMouseEvents == false)
    }

    @Test @MainActor
    func panelReceivesMouseEventsWhenPopping() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        vm.status = .popping
        panel.syncIgnoresMouseEvents()
        #expect(panel.ignoresMouseEvents == false)
    }

    @Test @MainActor
    func openingExpandsFrameToContainOpenedShelf() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        vm.status = .opened
        panel.syncFrameForStatus()
        #expect(panel.frame.width == geo.hoverTriggerRect.width)
        #expect(panel.frame.origin.x == geo.hoverTriggerRect.origin.x)
        #expect(panel.frame.maxY == geo.screenFrame.maxY)
        #expect(panel.frame.height >= geo.openedPanelSize.height)
    }

    @Test @MainActor
    func updateGeometryResizesFrameRespectingStatus() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        vm.status = .opened
        panel.syncFrameForStatus()
        let newGeo = NotchGeometry(
            notchRect: NSRect(x: 800, y: 950, width: 200, height: 32),
            activationZone: NSRect(x: 770, y: 890, width: 260, height: 102),
            screenFrame: NSRect(x: 0, y: 0, width: 1800, height: 1000),
            hasNotch: true
        )
        panel.updateGeometry(newGeo)
        #expect(panel.frame.width == newGeo.hoverTriggerRect.width)
        #expect(panel.frame.origin.x == newGeo.hoverTriggerRect.origin.x)
        #expect(panel.frame.maxY == newGeo.screenFrame.maxY)
        #expect(panel.frame.height >= newGeo.openedPanelSize.height)
    }
}
