import Testing
import AppKit
@testable import DropZoneLib

struct NotchDropForwarderTests {
    @Test @MainActor
    func hitTestReturnsSelfInsideFrame() {
        // hitTest must return a non-nil view for AppKit to deliver drag
        // events. Click-through is achieved at the window level via
        // ignoresMouseEvents, not via nil hitTest.
        let f = NotchDropForwarder(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(f.hitTest(NSPoint(x: 50, y: 50)) === f)
    }

    @Test @MainActor
    func sourceAppNameResolvesFinder() {
        #expect(NotchDropForwarder.sourceAppName(forBundleID: "com.apple.finder") == "Finder")
    }

    @Test @MainActor
    func sourceAppNameReturnsNilForUnknownBundleID() {
        #expect(NotchDropForwarder.sourceAppName(forBundleID: "com.example.no-such-app.fake") == nil)
    }
}
