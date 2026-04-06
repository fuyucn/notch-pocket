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

    // MARK: - Additional edge cases

    @Test("Stop then start observing again works correctly")
    func restartObservation() {
        let detector = ScreenDetector()
        detector.startObserving()
        detector.stopObserving()
        detector.startObserving()
        // Should be able to receive callbacks after restart
        var callbackCalled = false
        detector.onScreenChange = { _ in callbackCalled = true }
        detector.refresh()
        #expect(callbackCalled)
        detector.stopObserving()
    }

    @Test("Multiple rapid refresh calls produce consistent geometry")
    func multipleRefreshConsistency() {
        let detector = ScreenDetector()
        for _ in 0..<10 {
            detector.refresh()
        }
        // Geometry should still be valid after many refreshes
        #expect(detector.currentGeometry.screenFrame.width > 0)
        #expect(detector.currentGeometry.screenFrame.height > 0)
    }

    @Test("Callback receives geometry matching currentGeometry")
    func callbackMatchesCurrent() {
        let detector = ScreenDetector()
        var receivedGeometry: NotchGeometry?
        detector.onScreenChange = { geo in receivedGeometry = geo }
        detector.refresh()
        #expect(receivedGeometry != nil)
        #expect(receivedGeometry?.screenFrame == detector.currentGeometry.screenFrame)
        #expect(receivedGeometry?.hasNotch == detector.currentGeometry.hasNotch)
    }

    @Test("All screen geometries have non-zero activation zones")
    func allGeometriesHaveActivationZones() {
        let geometries = ScreenDetector.allScreenGeometries()
        for geo in geometries {
            #expect(geo.activationZone.width > 0)
            #expect(geo.activationZone.height > 0)
        }
    }

    @Test("Detector without callback does not crash on refresh")
    func refreshWithoutCallback() {
        let detector = ScreenDetector()
        detector.onScreenChange = nil
        detector.refresh() // Should not crash
        #expect(detector.currentGeometry.screenFrame.width > 0)
    }
}
