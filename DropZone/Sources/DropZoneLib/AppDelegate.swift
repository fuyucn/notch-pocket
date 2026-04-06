import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var screenDetector: ScreenDetector?
    private(set) public var dropZonePanel: DropZonePanel?
    private(set) public var fileShelfManager: FileShelfManager?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = StatusBarController()
        controller.setup()
        statusBarController = controller

        // Set up file shelf manager
        let shelfManager = FileShelfManager()
        try? shelfManager.ensureShelfDirectory()
        shelfManager.startExpiryTimer()
        fileShelfManager = shelfManager

        // Set up screen detection and panel
        let detector = ScreenDetector()
        let panel = DropZonePanel(geometry: detector.currentGeometry)

        // Wire drag destination to shelf manager
        panel.dragDestinationView.fileShelfManager = shelfManager
        panel.dragDestinationView.onFilesDropped = { [weak panel] count in
            panel?.playDropConfirmation {
                // After confirmation animation, collapse if desired
            }
        }

        detector.onScreenChange = { [weak panel] newGeometry in
            panel?.geometry = newGeometry
        }
        detector.startObserving()

        screenDetector = detector
        dropZonePanel = panel
    }

    public func applicationWillTerminate(_ notification: Notification) {
        fileShelfManager?.cleanupAll()
        fileShelfManager = nil

        screenDetector?.stopObserving()
        screenDetector = nil

        dropZonePanel?.hide()
        dropZonePanel = nil

        statusBarController?.teardown()
        statusBarController = nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
