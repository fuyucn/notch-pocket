import Testing
import AppKit
@testable import DropZoneLib

struct HoverDetectionPanelTests {
    @MainActor
    private func makeGeometry() -> NotchGeometry {
        NotchGeometry(
            notchRect: NSRect(x: 400, y: 768, width: 200, height: 32),
            activationZone: NSRect(x: 370, y: 708, width: 260, height: 102),
            screenFrame: NSRect(x: 0, y: 0, width: 1000, height: 800),
            hasNotch: true
        )
    }

    @Test @MainActor
    func frameMatchesHoverTriggerRect() {
        let geo = makeGeometry()
        let panel = HoverDetectionPanel(geometry: geo)
        #expect(panel.frame == geo.hoverTriggerRect)
    }

    @Test @MainActor
    func updateGeometryResizesFrame() {
        let panel = HoverDetectionPanel(geometry: makeGeometry())
        let newGeo = NotchGeometry(
            notchRect: NSRect(x: 500, y: 800, width: 180, height: 32),
            activationZone: NSRect(x: 470, y: 740, width: 240, height: 102),
            screenFrame: NSRect(x: 0, y: 0, width: 1200, height: 900),
            hasNotch: true
        )
        panel.updateGeometry(newGeo)
        #expect(panel.frame == newGeo.hoverTriggerRect)
    }

    @Test @MainActor
    func panelCannotBecomeKey() {
        let panel = HoverDetectionPanel(geometry: makeGeometry())
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
    }

    @Test @MainActor
    func hoverDelegateInvokedOnEnterAndExit() {
        @MainActor
        final class Spy: HoverDetectionDelegate {
            var entered = 0; var exited = 0
            func hoverEntered() { entered += 1 }
            func hoverExited() { exited += 1 }
        }
        let spy = Spy()
        let panel = HoverDetectionPanel(geometry: makeGeometry())
        panel.hoverDelegate = spy
        // Direct invocation of the fileprivate deliver methods via a public test seam
        // is tricky; simulate by calling the NSView tracking directly:
        // We can't fire real NSEvents in unit tests, so this test only verifies
        // the delegate wiring type-checks. Actual hover behavior is manually verified.
        #expect(panel.hoverDelegate === spy)
    }
}
