@preconcurrency import AppKit

/// Detects screen configuration changes and provides NotchGeometry for
/// all connected screens.
@MainActor
public final class ScreenDetector {
    /// Current geometry for the primary screen (backward compat).
    public private(set) var currentGeometry: NotchGeometry
    /// Geometries for all connected screens, keyed by screen's deviceDescription number.
    public private(set) var allGeometries: [CGDirectDisplayID: NotchGeometry] = [:]
    /// Callback when screen configuration changes (receives all geometries).
    public var onScreenChange: ((NotchGeometry) -> Void)?
    /// Callback when the full set of screens changes (added/removed/reconfigured).
    public var onAllScreensChanged: (([CGDirectDisplayID: NotchGeometry]) -> Void)?

    private var observer: NSObjectProtocol?

    public init() {
        currentGeometry = Self.detectPrimaryGeometry()
        allGeometries = Self.detectAllGeometries()
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
        allGeometries = Self.detectAllGeometries()
        onScreenChange?(newGeometry)
        onAllScreensChanged?(allGeometries)
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

    /// Build a dictionary of display ID → NotchGeometry for all screens.
    public static func detectAllGeometries() -> [CGDirectDisplayID: NotchGeometry] {
        var result: [CGDirectDisplayID: NotchGeometry] = [:]
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            result[displayID] = NotchGeometry(screen: screen)
        }
        return result
    }

    // MARK: - Private

    private func handleScreenChange() {
        let newGeometry = Self.detectPrimaryGeometry()
        currentGeometry = newGeometry
        allGeometries = Self.detectAllGeometries()
        onScreenChange?(newGeometry)
        onAllScreensChanged?(allGeometries)
    }
}

// MARK: - NSScreen helpers

extension NSScreen {
    /// The CGDirectDisplayID for this screen.
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Whether this is the built-in display (MacBook screen).
    var isBuiltIn: Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }
}
