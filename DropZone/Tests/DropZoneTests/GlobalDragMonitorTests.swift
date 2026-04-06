import Testing
import AppKit
@testable import DropZoneLib

@Suite("GlobalDragMonitor Tests")
@MainActor
struct GlobalDragMonitorTests {

    private func makeTestGeometry() -> NotchGeometry {
        let notchRect = NSRect(x: 700, y: 1390, width: 200, height: 32)
        return NotchGeometry(
            notchRect: notchRect,
            activationZone: NSRect(x: 680, y: 1350, width: 240, height: 72),
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )
    }

    // MARK: - Creation

    @Test("GlobalDragMonitor can be created")
    func creation() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        #expect(monitor.isDragActive == false)
        #expect(monitor.isInsideZone == false)
    }

    @Test("GlobalDragMonitor stores geometry")
    func storesGeometry() {
        let geo = makeTestGeometry()
        let monitor = GlobalDragMonitor(geometry: geo)
        #expect(monitor.geometry.hasNotch == true)
        #expect(monitor.geometry.screenFrame == geo.screenFrame)
    }

    // MARK: - Geometry update

    @Test("Geometry can be updated")
    func geometryUpdate() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        let newGeo = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(x: 840, y: 1008, width: 240, height: 72),
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            hasNotch: false
        )
        monitor.geometry = newGeo
        #expect(monitor.geometry.hasNotch == false)
    }

    // MARK: - Activation zone hit testing

    @Test("Point inside activation zone is detected")
    func pointInsideZone() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        // Center of the activation zone
        let point = NSPoint(x: 800, y: 1386)
        #expect(monitor.isPointInActivationZone(point))
    }

    @Test("Point outside activation zone is not detected")
    func pointOutsideZone() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        // Far from the activation zone
        let point = NSPoint(x: 100, y: 100)
        #expect(!monitor.isPointInActivationZone(point))
    }

    @Test("Activation zone includes drag proximity padding")
    func dragProximityPadding() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        // Point just below the normal activation zone but within padding
        // Normal activationZone bottom is y=1350, padding is 60, so y=1290 should be inside
        let point = NSPoint(x: 800, y: 1295)
        #expect(monitor.isPointInActivationZone(point))
    }

    @Test("Point below drag proximity padding is outside")
    func belowDragProximityPadding() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        // Normal activationZone bottom is y=1350, padding is 60, so y=1280 should be outside
        let point = NSPoint(x: 800, y: 1280)
        #expect(!monitor.isPointInActivationZone(point))
    }

    // MARK: - Start/Stop monitoring

    @Test("startMonitoring is idempotent")
    func startMonitoringIdempotent() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        monitor.startMonitoring()
        monitor.startMonitoring() // Should not crash or create duplicate monitors
        #expect(monitor.isDragActive == false)
        monitor.stopMonitoring()
    }

    @Test("stopMonitoring resets state")
    func stopMonitoringResetsState() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        monitor.startMonitoring()
        monitor.stopMonitoring()
        #expect(monitor.isDragActive == false)
        #expect(monitor.isInsideZone == false)
    }

    @Test("stopMonitoring is safe when not started")
    func stopWithoutStart() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        monitor.stopMonitoring() // Should not crash
        #expect(monitor.isDragActive == false)
    }

    // MARK: - Callbacks

    @Test("Callbacks can be set")
    func callbacksCanBeSet() {
        let monitor = GlobalDragMonitor(geometry: makeTestGeometry())
        nonisolated(unsafe) var entered = false
        nonisolated(unsafe) var exited = false
        nonisolated(unsafe) var began = false
        nonisolated(unsafe) var ended = false

        monitor.onDragEnteredZone = { entered = true }
        monitor.onDragExitedZone = { exited = true }
        monitor.onDragBegan = { began = true }
        monitor.onDragEnded = { ended = true }

        // Callbacks are set but not fired
        #expect(!entered)
        #expect(!exited)
        #expect(!began)
        #expect(!ended)
    }

    // MARK: - Poll interval

    @Test("Poll interval is approximately 30fps")
    func pollInterval() {
        let interval = GlobalDragMonitor.pollInterval
        #expect(interval > 0.03)
        #expect(interval < 0.04)
    }

    // MARK: - Drag proximity padding

    @Test("Drag proximity padding is 60pt")
    func dragProximityPaddingValue() {
        #expect(GlobalDragMonitor.dragProximityPadding == 60)
    }
}
