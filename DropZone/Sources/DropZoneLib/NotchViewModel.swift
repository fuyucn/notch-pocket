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

    public var geometry: NotchGeometry

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

    /// Drive the status from a pointer location + drag flag.
    public func updateMouseLocation(_ point: NSPoint, isDragging: Bool) {
        if let deadline = openStickyUntil, Date() < deadline {
            if status != .opened { status = .opened }
            return
        } else if openStickyUntil != nil {
            openStickyUntil = nil  // expired, resume normal logic
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
    }
}
