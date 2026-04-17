import Testing
import AppKit
@testable import DropZoneLib

struct EventMonitorsTests {
    @Test @MainActor
    func sharedIsSingleton() {
        #expect(EventMonitors.shared === EventMonitors.shared)
    }

    @Test @MainActor
    func mouseLocationPublisherIsFinite() {
        let current = EventMonitors.shared.mouseLocation.value
        #expect(current.x.isFinite)
        #expect(current.y.isFinite)
    }

    @Test @MainActor
    func isDraggingPublisherHasBoolValue() {
        let value = EventMonitors.shared.isDragging.value
        #expect(value == true || value == false)
    }
}
