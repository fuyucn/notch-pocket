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
    /// True when a file drag is currently inside the panel's drop forwarder —
    /// used to highlight the drop target (dashed border, fill) in the opened UI.
    @Published public var isDragInside: Bool = false
    /// AirDrop button frame in global screen coordinates, reported by SwiftUI
    /// via GeometryReader. `nil` when the button isn't on screen. Used by
    /// `NotchDropForwarder` to steer drops on the AirDrop region to AirDrop
    /// instead of the shelf.
    public var airDropRectInPanel: NSRect?
    /// True while the drag cursor is inside `airDropRectInPanel`. Published
    /// so the AirDrop button can highlight.
    @Published public var isDragOverAirDrop: Bool = false
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

    /// Open the shelf. Stays open until `forceClose()` is called (close button,
    /// click-outside, Esc). The `stickyFor` parameter is accepted for source
    /// compatibility but ignored — opened state no longer auto-dismisses.
    public func markDropped(stickyFor seconds: TimeInterval = 0) {
        _ = seconds
        status = .opened
        openStickyUntil = nil
    }

    /// Drive the status from a pointer location + drag flag.
    /// When already `.opened`, this is a no-op — the shelf is explicitly
    /// dismissed via `forceClose()`.
    public func updateMouseLocation(_ point: NSPoint, isDragging: Bool) {
        if status == .opened {
            return
        }
        guard isDragging else {
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
        openStickyUntil = nil
    }
}
