import AppKit
import SwiftUI

/// Manages the settings window lifecycle.
///
/// Hosts the SwiftUI `SettingsView` in an NSWindow and ensures
/// only a single settings window is open at a time.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private var windowCloseDelegate: WindowCloseDelegate?
    private let settingsManager: SettingsManager

    public init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    /// Show the settings window, creating it if needed.
    /// Brings the window to front and activates the app.
    public func showSettings() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settingsManager: settingsManager)
        let hostingView = NSHostingView(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "DropZone Settings"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        let closeDelegate = WindowCloseDelegate { [weak self] in
            self?.window = nil
            self?.windowCloseDelegate = nil
        }
        windowCloseDelegate = closeDelegate
        newWindow.delegate = closeDelegate

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    /// Close the settings window if open.
    public func closeSettings() {
        window?.close()
        window = nil
    }

    public var isOpen: Bool {
        window?.isVisible ?? false
    }
}

/// Lightweight delegate to detect window close and nil out the reference.
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            onClose()
        }
    }
}
