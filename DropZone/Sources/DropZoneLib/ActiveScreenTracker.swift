import AppKit
import Combine

/// Tracks which `NSScreen` hosts the user's current foreground app so panels
/// can be relocated onto that screen. Listens for front-app and window
/// activation notifications, plus screen reconfiguration.
///
/// Consumers subscribe to `activeScreen` to react to changes.
@MainActor
public final class ActiveScreenTracker {
    public static let shared = ActiveScreenTracker()

    public let activeScreen: CurrentValueSubject<NSScreen?, Never>

    private var isRunning = false
    private var observers: [(NSObjectProtocol, NotificationCenter)] = []

    public init() {
        self.activeScreen = CurrentValueSubject<NSScreen?, Never>(Self.computeActiveScreen())
    }

    /// Subscribe to AppKit notifications. Idempotent.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let nc = NotificationCenter.default
        let wsNC = NSWorkspace.shared.notificationCenter

        observers.append((wsNC.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }, wsNC))

        observers.append((nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }, nc))

        observers.append((nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }, nc))
    }

    /// Unsubscribe. Idempotent.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        for (token, center) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    private func recompute() {
        // Dedupe by frame — AppKit may return fresh NSScreen instances after
        // `didChangeScreenParameters`, so identity comparison would spuriously
        // fire. Frame is stable as long as the physical screen is the same.
        let new = Self.computeActiveScreen()
        if new?.frame != activeScreen.value?.frame {
            activeScreen.send(new)
        }
    }

    /// Priority: last key-window screen (surfaced by `NSScreen.main`) →
    /// first notched screen → first screen. Returns `nil` only when
    /// `NSScreen.screens` is empty.
    public static func computeActiveScreen() -> NSScreen? {
        if let main = NSScreen.main { return main }
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top != 0 }) {
            return notched
        }
        return NSScreen.screens.first
    }
}
