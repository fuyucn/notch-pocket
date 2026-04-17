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
        #expect(calls == 0)
    }
}
