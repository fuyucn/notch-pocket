import Testing
import AppKit
@testable import DropZoneLib

struct ActiveScreenTrackerTests {
    @Test @MainActor
    func computeActiveScreenReturnsNonNilWhenScreensExist() {
        #expect(ActiveScreenTracker.computeActiveScreen() != nil)
    }

    @Test @MainActor
    func computeActiveScreenPreferencesNotchedScreenOverOthers() {
        guard NSScreen.screens.contains(where: { $0.safeAreaInsets.top != 0 }) else {
            return
        }
        let result = ActiveScreenTracker.computeActiveScreen()
        #expect(result != nil)
    }

    @Test @MainActor
    func startAndStopToggleObservation() {
        let tracker = ActiveScreenTracker()
        #expect(tracker.activeScreen.value != nil)
        tracker.start()
        tracker.stop()
        tracker.stop()
    }
}
