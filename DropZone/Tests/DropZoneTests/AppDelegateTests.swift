import Testing
import AppKit
@testable import DropZoneLib

@Suite("AppDelegate Tests")
@MainActor
struct AppDelegateTests {
    @Test("AppDelegate can be created")
    func appDelegateCreation() {
        let delegate = AppDelegate()
        let _: NSApplicationDelegate = delegate
    }

    @Test("App should not terminate after last window closed")
    func shouldNotTerminateAfterLastWindowClosed() {
        let delegate = AppDelegate()
        let result = delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        #expect(result == false)
    }

    @Test("AppDelegate has no status bar controller before launch")
    func statusBarControllerNilBeforeLaunch() {
        let delegate = AppDelegate()
        #expect(delegate.statusBarController == nil)
    }
}

@Suite("StatusBarController Tests")
@MainActor
struct StatusBarControllerTests {
    @Test("StatusBarController can be created")
    func creation() {
        let controller = StatusBarController()
        #expect(controller.isVisible == false)
    }

    @Test("StatusBarController setup makes it visible")
    func setupMakesVisible() {
        let controller = StatusBarController()
        controller.setup()
        #expect(controller.isVisible == true)
        controller.teardown()
    }

    @Test("StatusBarController teardown makes it invisible")
    func teardownMakesInvisible() {
        let controller = StatusBarController()
        controller.setup()
        controller.teardown()
        #expect(controller.isVisible == false)
    }

    @Test("StatusBarController double teardown is safe")
    func doubleTeardownIsSafe() {
        let controller = StatusBarController()
        controller.setup()
        controller.teardown()
        controller.teardown()
        #expect(controller.isVisible == false)
    }
}

@Suite("Sanity Tests")
struct SanityTests {
    @Test("DropZoneLib module loads")
    func moduleLoads() {
        // If this test compiles and runs, the DropZoneLib module is loadable
        #expect(true)
    }

    @MainActor
    @Test("AppDelegate conforms to NSApplicationDelegate")
    func appDelegateConformance() {
        let delegate = AppDelegate()
        #expect(delegate is NSApplicationDelegate)
    }

    @MainActor
    @Test("StatusBarController full lifecycle")
    func fullLifecycle() {
        let controller = StatusBarController()
        #expect(controller.isVisible == false, "Should start invisible")
        controller.setup()
        #expect(controller.isVisible == true, "Should be visible after setup")
        controller.teardown()
        #expect(controller.isVisible == false, "Should be invisible after teardown")
    }
}
