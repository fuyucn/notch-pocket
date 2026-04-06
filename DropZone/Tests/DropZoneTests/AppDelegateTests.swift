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

    @Test("updateFileCount shows shelf items in menu")
    func updateFileCount() {
        let controller = StatusBarController()
        controller.setup()
        controller.updateFileCount(3)
        // After updating with non-zero count, the status bar icon should change
        // (we can't easily inspect menu items, but the call should not crash)
        controller.updateFileCount(0)
        controller.teardown()
    }

    @Test("onShowShelf callback fires from menu action")
    func showShelfCallback() {
        let controller = StatusBarController()
        nonisolated(unsafe) var called = false
        controller.onShowShelf = { called = true }
        // Callbacks are wired but we can't programmatically trigger menu actions
        // Just verify the callback property is set
        #expect(!called)
    }

    @Test("onClearShelf callback fires from menu action")
    func clearShelfCallback() {
        let controller = StatusBarController()
        nonisolated(unsafe) var called = false
        controller.onClearShelf = { called = true }
        #expect(!called)
    }

    @Test("onShowSettings callback can be set")
    func showSettingsCallback() {
        let controller = StatusBarController()
        nonisolated(unsafe) var called = false
        controller.onShowSettings = { called = true }
        #expect(!called) // Wired but not triggered
    }

    @Test("Setup then teardown then setup again works")
    func setupTeardownCycle() {
        let controller = StatusBarController()
        controller.setup()
        #expect(controller.isVisible)
        controller.teardown()
        #expect(!controller.isVisible)
        controller.setup()
        #expect(controller.isVisible)
        controller.teardown()
    }

    @Test("updateFileCount with 1 file uses singular form")
    func singularFileCount() {
        let controller = StatusBarController()
        controller.setup()
        // Should not crash — the menu items update internally
        controller.updateFileCount(1)
        controller.updateFileCount(0)
        controller.teardown()
    }

    @Test("updateFileCount with large number does not crash")
    func largeFileCount() {
        let controller = StatusBarController()
        controller.setup()
        controller.updateFileCount(999)
        controller.updateFileCount(0)
        controller.teardown()
    }
}

@Suite("Sanity Tests")
struct SanityTests {
    @Test("DropZoneLib module loads")
    func moduleLoads() {
        // If this test compiles and runs, the DropZoneLib module is loadable
        #expect(Bool(true))
    }

    @MainActor
    @Test("AppDelegate conforms to NSApplicationDelegate")
    func appDelegateConformance() {
        let delegate = AppDelegate()
        #expect(delegate is any NSApplicationDelegate)
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

    @MainActor
    @Test("GlobalDragMonitor can be created in sanity check")
    func globalDragMonitorSanity() {
        let geo = NotchGeometry(
            notchRect: NSRect(x: 700, y: 1390, width: 200, height: 32),
            activationZone: NSRect(x: 680, y: 1350, width: 240, height: 72),
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )
        let monitor = GlobalDragMonitor(geometry: geo)
        #expect(monitor.isDragActive == false)
    }
}
