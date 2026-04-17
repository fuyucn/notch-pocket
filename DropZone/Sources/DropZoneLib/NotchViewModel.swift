import AppKit
import Combine

@MainActor
public final class NotchViewModel: ObservableObject {
    public enum Status: Sendable, Equatable {
        case closed
        case popping
        case opened
    }

    @Published public var status: Status = .closed
    @Published public var primaryFileName: String?
    @Published public var extraCount: Int = 0
    @Published public var shelfCount: Int = 0
    /// Set true by `NotchDropForwarder.draggingEntered` when a real file drag
    /// arrives, false on `draggingExited` / drop. Only this flag (not the
    /// generic `leftMouseDragged` state from EventMonitors) decides whether
    /// moving the cursor into the hover rect should pop the panel — otherwise
    /// ordinary window-move / text-select drags would trigger it.
    @Published public var isFileDragging: Bool = false
    /// Incremented whenever the shelf content changes, so SwiftUI consumers can
    /// re-bind their NSViewRepresentable to pick up manager state.
    @Published public var shelfRefreshToken: Int = 0

    public var geometry: NotchGeometry

    /// Weak reference to the shelf manager. Set by AppDelegate; used by
    /// SwiftUI to bind `ShelfContainerView` in the opened state.
    public weak var shelfManager: FileShelfManager?

    /// Weak reference to the app's settings manager. Set by AppDelegate.
    public weak var settingsManager: SettingsManager?

    /// When non-nil, `updateMouseLocation` ignores the drag gate and keeps `.opened`
    /// until this deadline passes.
    private var openStickyUntil: Date?

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    public func markDropped(stickyFor seconds: TimeInterval = 2.5) {
        status = .opened
        openStickyUntil = Date().addingTimeInterval(seconds)
    }

    /// Drive the status from a pointer location. The `isDragging` parameter
    /// originated from a generic `.leftMouseDragged` monitor which fires for
    /// ANY drag (window move, text select, etc.); it is therefore ignored
    /// here in favor of `isFileDragging`, which is only set true when a real
    /// file drag enters our panel (via `NotchDropForwarder`).
    public func updateMouseLocation(_ point: NSPoint, isDragging: Bool) {
        if let deadline = openStickyUntil, Date() < deadline {
            if status != .opened { status = .opened }
            return
        } else if openStickyUntil != nil {
            openStickyUntil = nil  // expired, resume normal logic
        }
        guard isFileDragging else {
            if status != .closed { status = .closed }
            return
        }
        if geometry.activationZone.contains(point) {
            if status != .opened { status = .opened }
        } else if geometry.hoverTriggerRect.contains(point) {
            if status != .popping { status = .popping }
        } else {
            if status != .closed { status = .closed }
        }
    }

    public func forceClose() {
        status = .closed
    }
}
