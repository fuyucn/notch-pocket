import Testing
import AppKit
@testable import DropZoneLib

struct AppDelegateTests {
    @Test @MainActor
    func appDelegateExposesMinimizedPanel() {
        // AppDelegate bails early if no screen is available; skip on headless.
        guard NSScreen.main != nil else { return }
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("test")))
        #expect(delegate.minimizedPanel != nil)
        // Clean up so the test doesn't leave windows hanging around.
        delegate.applicationWillTerminate(Notification(name: Notification.Name("test")))
    }
}
