import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController()
        controller.setup()
        statusBarController = controller
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.teardown()
        statusBarController = nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
