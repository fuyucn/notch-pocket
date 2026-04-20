import AppKit
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) public var statusBarController: StatusBarController?
    private(set) public var notchViewModel: NotchViewModel?
    private(set) public var notchPanel: NotchPanel?
    private(set) public var fileShelfManager: FileShelfManager?
    private(set) public var settingsManager: SettingsManager?
    private(set) public var settingsWindowController: SettingsWindowController?
    private(set) public var keyboardShortcutManager: KeyboardShortcutManager?
    private(set) public var minimizedPanel: MinimizedPanel?
    private(set) public var activeScreenTracker: ActiveScreenTracker?
    private var activeScreenCancellable: AnyCancellable?
    private var fallbackNotchSize: NSSize = NotchGeometry.fallbackPillSize

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

        // Status bar is created first so the tray icon is present even if
        // screen geometry setup fails for any reason (headless, etc).
        let controller = StatusBarController()
        controller.setup()
        controller.updateFileCount(shelfManager.items.count)
        controller.onClearShelf = { [weak shelfManager] in shelfManager?.clearAll() }
        statusBarController = controller

        // Prefer a notched screen's notch dimensions as the canonical DropZone
        // capsule size. When jumping to non-notched screens later we reuse these
        // dimensions so the capsule looks identical regardless of display.
        let notchedScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 })
        if let notched = notchedScreen {
            let geom = NotchGeometry(screen: notched)
            if let notchRect = geom.notchRect {
                fallbackNotchSize = notchRect.size
            }
        }

        // Active screen at launch = whatever ActiveScreenTracker currently reports.
        let tracker = ActiveScreenTracker()
        activeScreenTracker = tracker
        guard let startupScreen = tracker.activeScreen.value else {
            return
        }
        let geometry = NotchGeometry(screen: startupScreen, fallbackNotchSize: fallbackNotchSize)

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

        // Wire up shelf-count → controller + view model.
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

        tracker.start()
        activeScreenCancellable = tracker.activeScreen
            .dropFirst()   // skip initial value (already applied)
            .sink { [weak self, weak panel, weak minimized, weak vm] newScreen in
                guard let self, let panel, let minimized, let vm,
                      let newScreen else { return }
                // requestClose() unconditionally transitions to .minimized or
                // .closed — safe on both .opened and .popping.
                if vm.status == .opened || vm.status == .popping {
                    vm.requestClose()
                }
                let newGeo = NotchGeometry(
                    screen: newScreen,
                    fallbackNotchSize: self.fallbackNotchSize
                )
                panel.updateGeometry(newGeo)
                minimized.updateGeometry(newGeo)
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
        activeScreenCancellable?.cancel()
        activeScreenCancellable = nil
        activeScreenTracker?.stop()
        activeScreenTracker = nil
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
