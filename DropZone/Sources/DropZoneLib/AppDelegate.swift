import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var notchViewModel: NotchViewModel?
    private(set) public var notchPanel: NotchPanel?
    private(set) public var fileShelfManager: FileShelfManager?
    private(set) public var settingsManager: SettingsManager?
    private(set) public var settingsWindowController: SettingsWindowController?
    private(set) public var keyboardShortcutManager: KeyboardShortcutManager?
    private(set) public var minimizedPanel: MinimizedPanel?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsManager()
        settingsManager = settings

        let shelfManager = FileShelfManager(
            storageModeProvider: { [weak settings] in settings?.storageMode ?? .reference }
        )
        shelfManager.maxItems = settings.maxShelfItems
        shelfManager.maxTotalBytes = settings.maxStorageBytes
        shelfManager.expiryInterval = settings.expiryInterval
        try? shelfManager.ensureShelfDirectory()
        shelfManager.validateItems() // Drop stale reference-mode entries on launch
        shelfManager.startExpiryTimer()
        fileShelfManager = shelfManager

        // Primary-screen geometry — multi-display is future work.
        guard let primaryScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 }) ?? NSScreen.main else {
            return
        }
        let geometry = NotchGeometry(screen: primaryScreen)

        let vm = NotchViewModel(geometry: geometry)
        vm.shelfCount = shelfManager.items.count
        vm.shelfManager = shelfManager
        vm.settingsManager = settings
        vm.status = shelfManager.items.count > 0 ? .minimized : .closed
        notchViewModel = vm

        let panel = NotchPanel(viewModel: vm)
        notchPanel = panel

        let minimized = MinimizedPanel(viewModel: vm)
        minimizedPanel = minimized

        // Drop handling
        panel.dropForwarder?.onDraggingChanged = { [weak vm] inside, names in
            guard let vm else { return }
            vm.isDragInside = inside
            vm.primaryFileName = inside ? names.first : nil
            vm.extraCount = inside ? max(0, names.count - 1) : 0
            if !inside { vm.isDragOverAirDrop = false }
        }
        panel.dropForwarder?.onDragMoved = { [weak vm] pointInView in
            guard let vm else { return }
            if let rect = vm.airDropRectInPanel {
                vm.isDragOverAirDrop = rect.contains(pointInView)
            } else {
                vm.isDragOverAirDrop = false
            }
        }
        panel.dropForwarder?.airDropRectProvider = { [weak vm] in
            vm?.airDropRectInPanel
        }
        panel.dropForwarder?.onDropOnAirDrop = { [weak vm] urls in
            vm?.isDragInside = false
            vm?.isDragOverAirDrop = false
            AirDropService.share(urls: urls)
            return true
        }
        panel.dropForwarder?.onDropFiles = { [weak shelfManager, weak vm] urls, appName in
            guard let shelfManager else { return false }
            let added = shelfManager.addFiles(from: urls, sourceAppName: appName)
            if !added.isEmpty {
                vm?.isDragInside = false
                vm?.primaryFileName = nil
                vm?.extraCount = 0
                vm?.isDragOverAirDrop = false
                vm?.markDropped()
                return true
            }
            return false
        }

        // Keep shelfCount synced with shelf manager
        shelfManager.onItemsChanged = { [weak vm, weak shelfManager] in
            guard let vm, let shelfManager else { return }
            vm.shelfCount = shelfManager.items.count
        }

        // Status bar
        let controller = StatusBarController()
        controller.setup()
        controller.updateFileCount(shelfManager.items.count)
        controller.onClearShelf = { [weak shelfManager] in shelfManager?.clearAll() }
        let previousOnItemsChanged = shelfManager.onItemsChanged
        shelfManager.onItemsChanged = { [weak controller, weak shelfManager, weak vm] in
            previousOnItemsChanged?()
            guard let shelfManager else { return }
            let count = shelfManager.items.count
            controller?.updateFileCount(count)
            guard let vm else { return }
            vm.shelfCount = count
            vm.shelfRefreshToken &+= 1
            // Auto-promote closed → minimized when shelf gains first file while idle.
            if count > 0, vm.status == .closed { vm.status = .minimized }
            // Auto-demote minimized → closed when shelf goes empty.
            if count == 0, vm.status == .minimized { vm.status = .closed }
        }
        statusBarController = controller

        // Settings window
        let settingsWindow = SettingsWindowController(settingsManager: settings)
        settingsWindowController = settingsWindow
        controller.onShowSettings = { [weak settingsWindow] in settingsWindow?.showSettings() }
        controller.onShowShelf = { [weak vm] in
            guard let vm else { return }
            vm.status = .opened
            vm.markDropped(stickyFor: 4)   // give user a moment to interact
        }

        settings.onSettingsChanged = { [weak shelfManager] in
            guard let shelfManager else { return }
            shelfManager.maxItems = settings.maxShelfItems
            shelfManager.maxTotalBytes = settings.maxStorageBytes
            shelfManager.expiryInterval = settings.expiryInterval
        }

        // Global hotkey — keep Cmd+Shift+D working as a simple "force open" stub
        let shortcuts = KeyboardShortcutManager()
        shortcuts.onToggleShelf = { [weak vm] in
            guard let vm else { return }
            vm.status = (vm.status == .opened) ? .closed : .opened
        }
        shortcuts.register()
        keyboardShortcutManager = shortcuts
    }

    public func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcutManager?.unregister()
        keyboardShortcutManager = nil
        settingsWindowController?.closeSettings()
        settingsWindowController = nil
        fileShelfManager?.cleanupAll()
        fileShelfManager = nil
        notchPanel?.orderOut(nil)
        notchPanel = nil
        minimizedPanel?.orderOut(nil)
        minimizedPanel = nil
        notchViewModel = nil
        statusBarController?.teardown()
        statusBarController = nil
        settingsManager = nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
