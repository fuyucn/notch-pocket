import Testing
import AppKit
@testable import DropZoneLib

@Suite("ScreenDetector Tests")
@MainActor
struct ScreenDetectorTests {

    @Test("ScreenDetector initializes with valid geometry")
    func creation() {
        let detector = ScreenDetector()
        #expect(detector.currentGeometry.screenFrame.width > 0)
        #expect(detector.currentGeometry.screenFrame.height > 0)
    }

    @Test("Start and stop observing is safe including double calls")
    func startStopObserving() {
        let detector = ScreenDetector()
        detector.startObserving()
        // Double start should be safe
        detector.startObserving()
        detector.stopObserving()
        // Double stop should be safe
        detector.stopObserving()
    }

    @Test("Refresh updates geometry with valid values")
    func refreshUpdatesGeometry() {
        let detector = ScreenDetector()
        let initialFrame = detector.currentGeometry.screenFrame

        detector.refresh()
        // After refresh, geometry should still be valid
        #expect(detector.currentGeometry.screenFrame.width > 0)
        // Frame should match (screen hasn't changed)
        #expect(detector.currentGeometry.screenFrame == initialFrame)
    }

    @Test("onScreenChange callback fires on refresh")
    func onScreenChangeCallback() {
        let detector = ScreenDetector()
        var callbackCalled = false

        detector.onScreenChange = { geometry in
            callbackCalled = true
            #expect(geometry.screenFrame.width > 0)
        }

        detector.refresh()
        #expect(callbackCalled)
    }

    @Test("detectPrimaryGeometry returns valid geometry")
    func detectPrimaryGeometry() {
        let geometry = ScreenDetector.detectPrimaryGeometry()
        #expect(geometry.screenFrame.width > 0)
        #expect(geometry.screenFrame.height > 0)
    }

    @Test("allScreenGeometries returns one entry per screen")
    func allScreenGeometries() {
        let geometries = ScreenDetector.allScreenGeometries()
        #expect(geometries.count == NSScreen.screens.count)
        for geo in geometries {
            #expect(geo.screenFrame.width > 0)
        }
    }
}
