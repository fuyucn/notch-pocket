import AppKit

@MainActor
public final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let menu: NSMenu

    // MARK: - Menu items that update dynamically

    private var fileCountItem: NSMenuItem?
    private var clearShelfItem: NSMenuItem?
    private var showShelfItem: NSMenuItem?

    // MARK: - Callbacks

    /// Called when the user selects "Show Shelf" from the menu.
    public var onShowShelf: (@MainActor () -> Void)?
    /// Called when the user selects "Clear Shelf" from the menu.
    public var onClearShelf: (@MainActor () -> Void)?
    /// Called when the user selects "Settings…" from the menu.
    public var onShowSettings: (@MainActor () -> Void)?

    // MARK: - Init

    public init() {
        menu = NSMenu()
        setupMenu()
    }

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "DropZone")
        }
        statusItem?.menu = menu
    }

    public func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    public var isVisible: Bool {
        statusItem != nil
    }

    // MARK: - Dynamic updates

    /// Update the menu to reflect the current shelf file count.
    public func updateFileCount(_ count: Int) {
        if count > 0 {
            fileCountItem?.title = "\(count) file\(count == 1 ? "" : "s") on shelf"
            fileCountItem?.isHidden = false
            clearShelfItem?.isHidden = false
            showShelfItem?.isHidden = false

            // Update status bar icon to indicate files are stored
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "DropZone – \(count) files")
            }
        } else {
            fileCountItem?.isHidden = true
            clearShelfItem?.isHidden = true
            showShelfItem?.isHidden = true

            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "DropZone")
            }
        }
    }

    // MARK: - Menu setup

    private func setupMenu() {
        // File count (dynamic, hidden when 0)
        let countItem = NSMenuItem(title: "0 files on shelf", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        countItem.isHidden = true
        menu.addItem(countItem)
        fileCountItem = countItem

        // Show shelf
        let showItem = NSMenuItem(title: "Show Shelf", action: #selector(showShelfAction(_:)), keyEquivalent: "s")
        showItem.target = self
        showItem.isHidden = true
        menu.addItem(showItem)
        showShelfItem = showItem

        // Clear shelf
        let clearItem = NSMenuItem(title: "Clear Shelf", action: #selector(clearShelfAction(_:)), keyEquivalent: "")
        clearItem.target = self
        clearItem.isHidden = true
        menu.addItem(clearItem)
        clearShelfItem = clearItem

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(settingsAction(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About DropZone", action: #selector(aboutAction(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DropZone", action: #selector(quitAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func showShelfAction(_ sender: NSMenuItem) {
        onShowShelf?()
    }

    @objc private func clearShelfAction(_ sender: NSMenuItem) {
        onClearShelf?()
    }

    @objc private func settingsAction(_ sender: NSMenuItem) {
        onShowSettings?()
    }

    @objc private func aboutAction(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitAction(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
