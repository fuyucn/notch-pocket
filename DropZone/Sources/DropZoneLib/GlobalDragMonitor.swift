import AppKit

/// Monitors system-wide drag events to auto-show the DropZone panel
/// when a file drag begins, and tracks mouse proximity to the notch area.
///
/// Uses `NSEvent.addGlobalMonitorForEvents` for drags outside the app
/// and `NSEvent.addLocalMonitorForEvents` for drags within the app.
/// A polling timer tracks the mouse position during active drags to
/// detect proximity to the activation zone.
@MainActor
public final class GlobalDragMonitor {
    // MARK: - Configuration

    /// How often to poll mouse position during an active drag (seconds).
    public static let pollInterval: TimeInterval = 1.0 / 30.0 // ~30 fps

    /// Extra vertical padding below activation zone for easier targeting during drags.
    public static let dragProximityPadding: CGFloat = 60

    // MARK: - Callbacks

    /// Called when a file drag enters the activation zone.
    public var onDragEnteredZone: (@MainActor () -> Void)?
    /// Called when a file drag exits the activation zone.
    public var onDragExitedZone: (@MainActor () -> Void)?
    /// Called when a system-wide drag session begins (any file drag).
    public var onDragBegan: (@MainActor () -> Void)?
    /// Called when a system-wide drag session ends.
    public var onDragEnded: (@MainActor () -> Void)?

    // MARK: - State

    /// Whether a system-wide file drag is currently active.
    public private(set) var isDragActive: Bool = false
    /// Whether the drag cursor is currently inside the activation zone.
    public private(set) var isInsideZone: Bool = false
    /// Current geometry used for activation zone hit testing.
    public var geometry: NotchGeometry

    // MARK: - Monitors

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollingTimer: Timer?

    // MARK: - Init

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // Cleanup is handled by stopMonitoring() called from AppDelegate.
    // deinit cannot safely access MainActor-isolated state in Swift 6.

    // MARK: - Start / Stop

    /// Start monitoring for system-wide drag events.
    public func startMonitoring() {
        guard globalMonitor == nil else { return }

        // Global monitor: catches drags happening outside our app windows.
        // We monitor mouse movement events — during a system drag, the system
        // sends these as the user moves the cursor.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleGlobalEvent(event)
            }
        }

        // Local monitor: catches drags within our own app windows.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalEvent(event)
            }
            return event
        }
    }

    /// Stop monitoring for drag events.
    public func stopMonitoring() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        stopPolling()
        resetState()
    }

    // MARK: - Pasteboard sniffing

    /// Check if the general pasteboard or drag pasteboard contains file URLs.
    /// This is used to distinguish file drags from other mouse drags.
    public func pasteboardHasFiles() -> Bool {
        let pb = NSPasteboard(name: .drag)
        if let types = pb.types {
            return types.contains(.fileURL) || types.contains(.filePromise)
        }
        return false
    }

    // MARK: - Hit testing

    /// Expand the activation zone with extra drag proximity padding.
    private func dragActivationZone() -> NSRect {
        let zone = geometry.activationZone
        return NSRect(
            x: zone.origin.x - Self.dragProximityPadding,
            y: zone.origin.y - Self.dragProximityPadding,
            width: zone.width + Self.dragProximityPadding * 2,
            height: zone.height + Self.dragProximityPadding
        )
    }

    /// Test whether a screen-coordinate point is inside the drag activation zone.
    public func isPointInActivationZone(_ point: NSPoint) -> Bool {
        dragActivationZone().contains(point)
    }

    // MARK: - Event handling

    private func handleGlobalEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            handleDragMovement()
        case .leftMouseUp:
            handleDragEnd()
        default:
            break
        }
    }

    private func handleLocalEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            handleDragMovement()
        case .leftMouseUp:
            handleDragEnd()
        default:
            break
        }
    }

    private func handleDragMovement() {
        if !isDragActive {
            // A drag just started — check if it's carrying files
            if pasteboardHasFiles() {
                isDragActive = true
                startPolling()
                onDragBegan?()
            }
        }
        // Position tracking is done by the polling timer
    }

    private func handleDragEnd() {
        guard isDragActive else { return }
        stopPolling()
        if isInsideZone {
            isInsideZone = false
            // Don't fire onDragExitedZone on drop — the DragDestinationView handles it
        }
        isDragActive = false
        onDragEnded?()
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollMousePosition()
            }
        }
        // Fire immediately for the first position
        pollMousePosition()
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let inZone = isPointInActivationZone(mouseLocation)

        if inZone && !isInsideZone {
            isInsideZone = true
            onDragEnteredZone?()
        } else if !inZone && isInsideZone {
            isInsideZone = false
            onDragExitedZone?()
        }
    }

    // MARK: - Reset

    private func resetState() {
        isDragActive = false
        isInsideZone = false
    }
}
