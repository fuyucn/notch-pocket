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
        #expect(panel.ignoresMouseEvents == true)
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
    func updateGeometryResizesFrame() {
        let geo = makeGeometry()
        let vm = NotchViewModel(geometry: geo)
        let panel = NotchPanel(viewModel: vm)
        let newGeo = NotchGeometry(
            notchRect: NSRect(x: 800, y: 950, width: 200, height: 32),
            activationZone: NSRect(x: 770, y: 890, width: 260, height: 102),
            screenFrame: NSRect(x: 0, y: 0, width: 1800, height: 1000),
            hasNotch: true
        )
        panel.updateGeometry(newGeo)
        #expect(panel.frame == newGeo.hoverTriggerRect)
    }
}
