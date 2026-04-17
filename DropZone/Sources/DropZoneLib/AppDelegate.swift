import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var notchViewModel: NotchViewModel?
    private(set) public var notchPanel: NotchPanel?
    private(set) public var fileShelfManager: FileShelfManager?
    private(set) public var settingsManager: SettingsManager?
    private(set) public var settingsWindowController: SettingsWindowController?
    private(set) public var keyboardShortcutManager: KeyboardShortcutManager?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsManager()
        settingsManager = settings

        let shelfManager = FileShelfManager()
        shelfManager.maxItems = settings.maxShelfItems
        shelfManager.maxTotalBytes = settings.maxStorageBytes
        shelfManager.expiryInterval = settings.expiryInterval
        try? shelfManager.ensureShelfDirectory()
        shelfManager.startExpiryTimer()
        fileShelfManager = shelfManager

        // Primary-screen geometry — multi-display is future work.
        guard let primaryScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 }) ?? NSScreen.main else {
            return
        }
        let geometry = NotchGeometry(screen: primaryScreen)

        let vm = NotchViewModel(geometry: geometry)
        vm.shelfCount = shelfManager.items.count
        notchViewModel = vm

        let panel = NotchPanel(viewModel: vm)
        notchPanel = panel

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
            controller?.updateFileCount(shelfManager.items.count)
            vm?.shelfCount = shelfManager.items.count
        }
        statusBarController = controller

        // Settings window
        let settingsWindow = SettingsWindowController(settingsManager: settings)
        settingsWindowController = settingsWindow
        controller.onShowSettings = { [weak settingsWindow] in settingsWindow?.showSettings() }

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
        notchViewModel = nil
        statusBarController?.teardown()
        statusBarController = nil
        settingsManager = nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
