@preconcurrency import AppKit

/// Detects screen configuration changes and provides NotchGeometry for
/// the primary screen (preferring the built-in notched display).
@MainActor
public final class ScreenDetector {
    /// Current geometry for the active screen.
    public private(set) var currentGeometry: NotchGeometry
    /// Callback when screen configuration changes and geometry is updated.
    public var onScreenChange: ((NotchGeometry) -> Void)?

    private var observer: NSObjectProtocol?

    public init() {
        currentGeometry = Self.detectPrimaryGeometry()
    }

    deinit {
        // Use nonisolated(unsafe) to safely access observer in deinit.
        // At deinit time, no other references exist, so this is safe.
        nonisolated(unsafe) let obs = observer
        if let obs {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Observation

    public func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }

    public func stopObserving() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }

    /// Force a refresh of geometry (e.g., after waking from sleep).
    public func refresh() {
        let newGeometry = Self.detectPrimaryGeometry()
        currentGeometry = newGeometry
        onScreenChange?(newGeometry)
    }

    // MARK: - Screen selection

    /// Find the best screen to anchor the panel to.
    /// Priority: built-in screen with notch > any screen with notch > main screen.
    public static func detectPrimaryGeometry() -> NotchGeometry {
        let screens = NSScreen.screens

        // Prefer built-in display with notch
        if let builtIn = screens.first(where: { $0.isBuiltIn && $0.safeAreaInsets.top != 0 }) {
            return NotchGeometry(screen: builtIn)
        }

        // Fall back to any screen with notch
        if let notched = screens.first(where: { $0.safeAreaInsets.top != 0 }) {
            return NotchGeometry(screen: notched)
        }

        // Fall back to main screen (the one with the key window / menu bar)
        if let main = NSScreen.main {
            return NotchGeometry(screen: main)
        }

        // Absolute fallback
        return NotchGeometry(screen: screens.first ?? NSScreen.screens[0])
    }

    /// Get geometry for all connected screens.
    public static func allScreenGeometries() -> [NotchGeometry] {
        NSScreen.screens.map { NotchGeometry(screen: $0) }
    }

    // MARK: - Private

    private func handleScreenChange() {
        let newGeometry = Self.detectPrimaryGeometry()
        currentGeometry = newGeometry
        onScreenChange?(newGeometry)
    }
}

// MARK: - NSScreen helpers

extension NSScreen {
    /// Whether this is the built-in display (MacBook screen).
    var isBuiltIn: Bool {
        // The built-in display has a stable display ID.
        // CGDisplayIsBuiltin checks the hardware display ID.
        let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return CGDisplayIsBuiltin(screenNumber) != 0
    }
}
