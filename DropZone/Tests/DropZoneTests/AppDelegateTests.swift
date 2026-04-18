import Testing
import AppKit
@testable import DropZoneLib

struct AppDelegateTests {
    @Test @MainActor
    func appDelegateExposesMinimizedPanel() {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("test")))
        #expect(delegate.minimizedPanel != nil)
        // Clean up so the test doesn't leave windows hanging around.
        delegate.applicationWillTerminate(Notification(name: Notification.Name("test")))
    }
}
