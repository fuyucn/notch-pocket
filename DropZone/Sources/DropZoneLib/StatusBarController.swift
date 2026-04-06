import AppKit

@MainActor
public final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let menu: NSMenu

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

    private func setupMenu() {
        let aboutItem = NSMenuItem(title: "About DropZone", action: #selector(aboutAction(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DropZone", action: #selector(quitAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func aboutAction(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitAction(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
