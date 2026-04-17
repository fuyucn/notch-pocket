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
