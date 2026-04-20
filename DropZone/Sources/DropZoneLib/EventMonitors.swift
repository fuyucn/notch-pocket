import AppKit
import Combine

/// Singleton event bus that publishes mouse position and drag state.
/// Subscribers react to Combine publishers; no callbacks, no global state
/// beyond the singleton itself.
@MainActor
public final class EventMonitors {
    public static let shared = EventMonitors()

    public let mouseLocation: CurrentValueSubject<NSPoint, Never>
    public let isDragging: CurrentValueSubject<Bool, Never>

    private var mouseMove: EventMonitor!
    private var mouseDown: EventMonitor!
    private var mouseDrag: EventMonitor!
    private var mouseUp: EventMonitor!

    /// Drag-pasteboard `changeCount` captured at mouse-down. Used to detect
    /// whether a new system drag session (Finder → our app) started during
    /// this press. A plain mouse drag (window move, text select) doesn't
    /// bump `changeCount`, so we can filter those out.
    private var pasteboardChangeCountAtMouseDown: Int = 0

    private init() {
        mouseLocation = CurrentValueSubject<NSPoint, Never>(NSEvent.mouseLocation)
        isDragging = CurrentValueSubject<Bool, Never>(false)

        mouseMove = EventMonitor(mask: [.mouseMoved]) { [weak self] _ in
            guard let self else { return }
            self.mouseLocation.send(NSEvent.mouseLocation)
        }
        mouseMove.start()

        mouseDown = EventMonitor(mask: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.pasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        }
        mouseDown.start()

        mouseDrag = EventMonitor(mask: [.leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            self.mouseLocation.send(NSEvent.mouseLocation)
            // Only treat this as a drag we care about if a real system drag
            // session has begun during this press (its pasteboard changeCount
            // has advanced since mouse-down) AND the pasteboard currently
            // carries a file. Plain mouse drags don't create a drag session.
            let isFileDrag = Self.isFileDragSessionActive(
                mouseDownCount: self.pasteboardChangeCountAtMouseDown
            )
            if self.isDragging.value != isFileDrag {
                self.isDragging.send(isFileDrag)
            }
        }
        mouseDrag.start()

        mouseUp = EventMonitor(mask: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            if self.isDragging.value == true { self.isDragging.send(false) }
        }
        mouseUp.start()
    }

    private static func isFileDragSessionActive(mouseDownCount: Int) -> Bool {
        let pb = NSPasteboard(name: .drag)
        // If no session has started since mouse-down, changeCount is unchanged.
        guard pb.changeCount > mouseDownCount else { return false }
        guard let types = pb.types else { return false }
        if types.contains(.fileURL) { return true }
        if types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) { return true }
        return false
    }
}
