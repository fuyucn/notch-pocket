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

    @Test @MainActor
    func sourceAppNameReturnsNilForUnknownBundleID() {
        #expect(NotchDropForwarder.sourceAppName(forBundleID: "com.example.no-such-app.fake") == nil)
    }
}
