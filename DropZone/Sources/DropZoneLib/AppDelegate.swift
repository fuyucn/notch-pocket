import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var screenDetector: ScreenDetector?
    private(set) public var dropZonePanel: DropZonePanel?
    private(set) public var fileShelfManager: FileShelfManager?
    private(set) public var dragMonitor: GlobalDragMonitor?
    private(set) public var settingsManager: SettingsManager?
    private(set) public var settingsWindowController: SettingsWindowController?
    private(set) public var keyboardShortcutManager: KeyboardShortcutManager?

    /// Timer to auto-hide the shelf after mouse leaves.
    private var hideShelfTimer: Timer?

    /// Delay before auto-hiding the shelf when mouse leaves (seconds).
    private static let hideShelfDelay: TimeInterval = 1.5

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Set up settings manager (must be first — other components read from it)
        let settings = SettingsManager()
        settingsManager = settings

        // Set up file shelf manager with settings-driven limits
        let shelfManager = FileShelfManager()
        shelfManager.maxItems = settings.maxShelfItems
        shelfManager.maxTotalBytes = settings.maxStorageBytes
        shelfManager.expiryInterval = settings.expiryInterval
        try? shelfManager.ensureShelfDirectory()
        shelfManager.startExpiryTimer()
        fileShelfManager = shelfManager

        // Set up screen detection and panel
        let detector = ScreenDetector()
        let panel = DropZonePanel(geometry: detector.currentGeometry)

        // Set up global drag monitor
        let monitor = GlobalDragMonitor(geometry: detector.currentGeometry)
        wireGlobalDragMonitor(monitor, panel: panel, shelfManager: shelfManager)
        monitor.startMonitoring()
        dragMonitor = monitor

        // Wire drag destination to shelf manager
        panel.dragDestinationView.fileShelfManager = shelfManager
        panel.dragDestinationView.onFilesDropped = { [weak panel, weak shelfManager] count in
            panel?.playDropConfirmation {
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

        // Wire panel hover for shelf reveal
        panel.onMouseEntered = { [weak self, weak panel, weak shelfManager] in
            guard let panel, let manager = shelfManager else { return }
            self?.cancelHideShelfTimer()
            if !manager.items.isEmpty && panel.panelState != .shelfExpanded {
                panel.fileShelfView.reload()
                panel.expandShelf()
            }
        }
        panel.onMouseExited = { [weak self, weak panel] in
            guard let panel else { return }
            // Only auto-hide if we're in shelf-expanded state from hover (not from a drop)
            if panel.panelState == .shelfExpanded {
                self?.scheduleHideShelf(panel: panel)
            }
        }
        panel.setupHoverTracking()

        // Update shelf view when items change externally (e.g. expiry)
        shelfManager.onItemsChanged = { [weak panel, weak shelfManager] in
            guard let panel, let manager = shelfManager else { return }
            panel.fileShelfView.reload()
            panel.updateBadge(count: manager.items.count)
        }

        // Screen changes → update geometry for panel and drag monitor
        detector.onScreenChange = { [weak panel, weak monitor] newGeometry in
            panel?.geometry = newGeometry
            monitor?.geometry = newGeometry
        }
        detector.startObserving()

        // Set up status bar controller
        let controller = StatusBarController()
        controller.setup()
        wireStatusBarController(controller, panel: panel, shelfManager: shelfManager)
        statusBarController = controller

        screenDetector = detector
        dropZonePanel = panel

        // Set up settings window controller
        let settingsWindow = SettingsWindowController(settingsManager: settings)
        settingsWindowController = settingsWindow

        // Wire settings menu item
        controller.onShowSettings = { [weak settingsWindow] in
            settingsWindow?.showSettings()
        }

        // React to settings changes — push new limits to shelf manager
        settings.onSettingsChanged = { [weak shelfManager, weak settings] in
            guard let manager = shelfManager, let s = settings else { return }
            manager.maxItems = s.maxShelfItems
            manager.maxTotalBytes = s.maxStorageBytes
            manager.expiryInterval = s.expiryInterval
        }

        // Set up global keyboard shortcut (Cmd+Shift+D to toggle shelf)
        let shortcuts = KeyboardShortcutManager()
        shortcuts.onToggleShelf = { [weak panel, weak shelfManager] in
            guard let panel, let manager = shelfManager else { return }
            if panel.panelState == .shelfExpanded {
                panel.collapse()
            } else if !manager.items.isEmpty {
                panel.fileShelfView.reload()
                panel.expandShelf()
            }
        }
        shortcuts.register()
        keyboardShortcutManager = shortcuts
    }

    public func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcutManager?.unregister()
        keyboardShortcutManager = nil

        settingsWindowController?.closeSettings()
        settingsWindowController = nil

        dragMonitor?.stopMonitoring()
        dragMonitor = nil

        hideShelfTimer?.invalidate()
        hideShelfTimer = nil

        fileShelfManager?.cleanupAll()
        fileShelfManager = nil

        screenDetector?.stopObserving()
        screenDetector = nil

        dropZonePanel?.hide()
        dropZonePanel = nil

        statusBarController?.teardown()
        statusBarController = nil

        settingsManager = nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Global drag monitor wiring

    @MainActor
    private func wireGlobalDragMonitor(
        _ monitor: GlobalDragMonitor,
        panel: DropZonePanel,
        shelfManager: FileShelfManager
    ) {
        // When a system-wide file drag begins, enter listening state
        monitor.onDragBegan = { [weak panel] in
            if panel?.panelState == .hidden {
                panel?.enterListening()
            }
        }

        // When a drag enters the outer pre-activation ring, show the narrow bar on that screen.
        monitor.onPreActivationEntered = { [weak panel, weak shelfManager] _, fileNames in
            guard let panel, let manager = shelfManager else { return }
            if panel.panelState == .listening || panel.panelState == .preActivated {
                panel.enterPreActivation(
                    primaryFileName: fileNames.first,
                    extraCount: max(0, fileNames.count - 1),
                    shelfCount: manager.items.count
                )
            }
        }

        monitor.onPreActivationExited = { [weak panel] _ in
            if panel?.panelState == .preActivated {
                panel?.exitPreActivation()
            }
        }

        // When the drag cursor enters the activation zone, expand the panel
        monitor.onDragEnteredZone = { [weak panel] _ in
            if panel?.panelState == .listening || panel?.panelState == .preActivated {
                panel?.expand()
            }
        }

        // When the drag cursor leaves the activation zone, collapse if not dropped
        monitor.onDragExitedZone = { [weak panel] _ in
            if panel?.panelState == .expanded {
                panel?.collapse()
            }
        }

        // When the drag session ends, return to hidden if still just listening or pre-activated
        monitor.onDragEnded = { [weak panel, weak self] in
            self?.cancelHideShelfTimer()
            if panel?.panelState == .listening || panel?.panelState == .preActivated {
                panel?.hide()
            }
        }
    }

    // MARK: - Status bar controller wiring

    @MainActor
    private func wireStatusBarController(
        _ controller: StatusBarController,
        panel: DropZonePanel,
        shelfManager: FileShelfManager
    ) {
        controller.onShowShelf = { [weak panel, weak shelfManager] in
            guard let panel, let manager = shelfManager else { return }
            if !manager.items.isEmpty {
                panel.fileShelfView.reload()
                panel.expandShelf()
            }
        }

        controller.onClearShelf = { [weak shelfManager] in
            shelfManager?.clearAll()
        }

        // Initial update
        controller.updateFileCount(shelfManager.items.count)

        // Keep status bar in sync with shelf changes
        let previousCallback = shelfManager.onItemsChanged
        shelfManager.onItemsChanged = { [weak controller, weak panel, weak shelfManager] in
            // Call the previously wired callback first
            previousCallback?()
            guard let manager = shelfManager else { return }
            controller?.updateFileCount(manager.items.count)
            panel?.fileShelfView.reload()
            panel?.updateBadge(count: manager.items.count)
        }
    }

    // MARK: - Auto-hide shelf timer

    @MainActor
    private func scheduleHideShelf(panel: DropZonePanel) {
        cancelHideShelfTimer()
        hideShelfTimer = Timer.scheduledTimer(
            withTimeInterval: Self.hideShelfDelay,
            repeats: false
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                if panel?.panelState == .shelfExpanded {
                    panel?.collapse()
                }
            }
        }
    }

    @MainActor
    private func cancelHideShelfTimer() {
        hideShelfTimer?.invalidate()
        hideShelfTimer = nil
    }
}
