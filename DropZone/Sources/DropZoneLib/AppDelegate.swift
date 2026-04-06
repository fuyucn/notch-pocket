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
        panel.dragDestinationView.onFilesDropped = { [weak panel, weak shelfManager] count in
            panel?.playDropConfirmation {
                // After confirmation, expand to show the shelf with thumbnails
                guard let panel, let manager = shelfManager else { return }
                panel.fileShelfView.animateAddItems(Array(manager.items.suffix(count)))
                panel.expandShelf()
            }
        }

        // Wire shelf view
        panel.fileShelfView.fileShelfManager = shelfManager
        panel.fileShelfView.onShelfEmpty = { [weak panel] in
            panel?.collapse()
        }
        panel.fileShelfView.onItemCountChanged = { [weak panel] count in
            if panel?.panelState == .hidden || panel?.panelState == .listening {
                panel?.updateBadge(count: count)
            }
        }

        // Update shelf view when items change externally (e.g. expiry)
        shelfManager.onItemsChanged = { [weak panel, weak shelfManager] in
            guard let panel, let manager = shelfManager else { return }
            panel.fileShelfView.reload()
            panel.updateBadge(count: manager.items.count)
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
