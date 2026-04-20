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
    private var observers: [NSObjectProtocol] = []

    public init() {
        self.activeScreen = CurrentValueSubject<NSScreen?, Never>(Self.computeActiveScreen())
    }

    /// Subscribe to AppKit notifications. Idempotent.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let nc = NotificationCenter.default
        let wsNC = NSWorkspace.shared.notificationCenter

        observers.append(wsNC.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })

        observers.append(nc.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })

        observers.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        })
    }

    /// Unsubscribe. Idempotent.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        let nc = NotificationCenter.default
        let wsNC = NSWorkspace.shared.notificationCenter
        for obs in observers {
            nc.removeObserver(obs)
            wsNC.removeObserver(obs)
        }
        observers.removeAll()
    }

    private func recompute() {
        let new = Self.computeActiveScreen()
        if activeScreen.value !== new {
            activeScreen.send(new)
        }
    }

    /// Priority: `NSScreen.main` (contains current key window, any app) →
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
