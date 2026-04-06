import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var screenDetector: ScreenDetector?
    /// All panels keyed by display ID.
    private(set) public var panels: [CGDirectDisplayID: DropZonePanel] = [:]
    /// Backward compat: the primary panel (built-in notch screen preferred).
    public var dropZonePanel: DropZonePanel? { panels.values.first }
    private(set) public var fileShelfManager: FileShelfManager?
    private(set) public var dragMonitor: GlobalDragMonitor?
    private(set) public var settingsManager: SettingsManager?
    private(set) public var settingsWindowController: SettingsWindowController?
    private(set) public var keyboardShortcutManager: KeyboardShortcutManager?

    /// Timers to auto-hide the shelf per panel.
    private var hideShelfTimers: [CGDirectDisplayID: Timer] = [:]

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

        // Set up screen detection
        let detector = ScreenDetector()

        // Create one panel per screen
        for (displayID, geo) in detector.allGeometries {
            let panel = createPanel(displayID: displayID, geometry: geo, shelfManager: shelfManager)
            panels[displayID] = panel
        }

        // Set up global drag monitor with all geometries
        let monitor = GlobalDragMonitor(geometry: detector.currentGeometry)
        monitor.allGeometries = detector.allGeometries
        wireGlobalDragMonitor(monitor, shelfManager: shelfManager)
        monitor.startMonitoring()
        dragMonitor = monitor

        // Update shelf view when items change externally (e.g. expiry)
        shelfManager.onItemsChanged = { [weak self, weak shelfManager] in
            guard let self, let manager = shelfManager else { return }
            for panel in self.panels.values {
                panel.fileShelfView.reload()
                panel.updateBadge(count: manager.items.count)
            }
        }

        // Screen changes → rebuild panels for new screen set
        detector.onAllScreensChanged = { [weak self, weak monitor, weak shelfManager] newGeometries in
            guard let self, let shelfManager else { return }
            self.reconcilePanels(newGeometries: newGeometries, shelfManager: shelfManager)
            monitor?.allGeometries = newGeometries
        }
        detector.onScreenChange = { [weak monitor] newGeometry in
            monitor?.geometry = newGeometry
        }
        detector.startObserving()

        // Set up status bar controller — wire to primary panel
        let controller = StatusBarController()
        controller.setup()
        wireStatusBarController(controller, shelfManager: shelfManager)
        statusBarController = controller

        screenDetector = detector

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

        // Set up global keyboard shortcut (Cmd+Shift+D to toggle shelf on primary panel)
        let shortcuts = KeyboardShortcutManager()
        shortcuts.onToggleShelf = { [weak self, weak shelfManager] in
            guard let self, let manager = shelfManager else { return }
            // Toggle shelf on the primary (notch) panel
            if let primaryPanel = self.panels.values.first(where: { $0.geometry.hasNotch }) ?? self.panels.values.first {
                if primaryPanel.panelState == .shelfExpanded {
                    primaryPanel.collapse()
                } else if !manager.items.isEmpty {
                    primaryPanel.fileShelfView.reload()
                    primaryPanel.expandShelf()
                }
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

        for timer in hideShelfTimers.values {
            timer.invalidate()
        }
        hideShelfTimers.removeAll()

        fileShelfManager?.cleanupAll()
        fileShelfManager = nil

        screenDetector?.stopObserving()
        screenDetector = nil

        for panel in panels.values {
            panel.hide()
        }
        panels.removeAll()

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
        shelfManager: FileShelfManager
    ) {
        // When a system-wide file drag begins, enter listening state on ALL panels
        monitor.onDragBegan = { [weak self] in
            guard let self else { return }
            for panel in self.panels.values {
                if panel.panelState == .hidden {
                    panel.enterListening()
                }
            }
        }

        // When the drag cursor enters a screen's activation zone, expand that panel
        monitor.onDragEnteredZone = { [weak self] displayID in
            guard let self, let panel = self.panels[displayID] else { return }
            if panel.panelState == .listening {
                panel.expand()
            }
        }

        // When the drag cursor leaves a screen's activation zone, collapse that panel
        monitor.onDragExitedZone = { [weak self] displayID in
            guard let self, let panel = self.panels[displayID] else { return }
            if panel.panelState == .expanded {
                panel.collapse()
            }
        }

        // When the drag session ends, return all panels to hidden if still listening
        monitor.onDragEnded = { [weak self] in
            guard let self else { return }
            for (displayID, _) in self.hideShelfTimers {
                self.cancelHideShelfTimer(for: displayID)
            }
            for panel in self.panels.values {
                if panel.panelState == .listening {
                    panel.hide()
                }
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
