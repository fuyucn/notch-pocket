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

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Drive the status from a pointer location + drag flag.
    public func updateMouseLocation(_ point: NSPoint, isDragging: Bool) {
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
