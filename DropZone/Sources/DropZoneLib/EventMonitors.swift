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
    private var mouseDrag: EventMonitor!
    private var mouseUp: EventMonitor!

    private init() {
        mouseLocation = CurrentValueSubject<NSPoint, Never>(NSEvent.mouseLocation)
        isDragging = CurrentValueSubject<Bool, Never>(false)

        mouseMove = EventMonitor(mask: [.mouseMoved]) { [weak self] _ in
            guard let self else { return }
            self.mouseLocation.send(NSEvent.mouseLocation)
        }
        mouseMove.start()

        mouseDrag = EventMonitor(mask: [.leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            self.mouseLocation.send(NSEvent.mouseLocation)
            if self.isDragging.value == false { self.isDragging.send(true) }
        }
        mouseDrag.start()

        mouseUp = EventMonitor(mask: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            if self.isDragging.value == true { self.isDragging.send(false) }
        }
        mouseUp.start()
    }
}
