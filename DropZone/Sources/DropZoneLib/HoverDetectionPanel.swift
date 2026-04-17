import AppKit

/// Delegate for hover events delivered by the HoverDetectionPanel.
@MainActor
public protocol HoverDetectionDelegate: AnyObject {
    func hoverEntered()
    func hoverExited()
}

/// Invisible, click-through NSPanel pinned at notch top whose only job is to
/// deliver `mouseEntered` / `mouseExited` to a delegate via NSTrackingArea.
/// No global event monitors — no TCC permission required.
@MainActor
public final class HoverDetectionPanel: NSPanel {
    public weak var hoverDelegate: HoverDetectionDelegate?

    private let trackingView = HoverTrackingView()

    public init(geometry: NotchGeometry) {
        // Use the pre-activation rect outset by 20px so the panel edges extend beyond the
        // DropZonePanel boundary — prevents mouseExited firing when DropZonePanel overlaps.
        let rect = geometry.preActivationRect.insetBy(dx: -20, dy: -20)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver  // Above .popUpMenu used by DropZonePanel — prevents flicker
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false // We need mouseEntered/mouseExited
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        trackingView.owner = self
        contentView = trackingView

        setFrame(geometry.preActivationRect.insetBy(dx: -20, dy: -20), display: false)
        orderFrontRegardless()
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        setFrame(geometry.preActivationRect.insetBy(dx: -20, dy: -20), display: true)
    }

    // Delegate invocation helpers called by the tracking view
    fileprivate func deliverEntered() { hoverDelegate?.hoverEntered() }
    fileprivate func deliverExited() { hoverDelegate?.hoverExited() }

    // We never want this panel to steal keyboard focus.
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    // Pass clicks through to what's underneath — we only care about hover.
    override public func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseEntered, .mouseExited, .mouseMoved:
            super.sendEvent(event)
        default:
            // Let clicks/scrolls flow to the windows below.
            break
        }
    }
}

@MainActor
private final class HoverTrackingView: NSView {
    weak var owner: HoverDetectionPanel?
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Register as a drag destination so tracking fires during drag sessions.
        // NSTrackingArea alone doesn't fire mouseEntered/mouseExited during a drag.
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .assumeInside],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { owner?.deliverEntered() }
    override func mouseExited(with event: NSEvent) { owner?.deliverExited() }

    // MARK: - NSDraggingDestination (drag-session hover detection)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        owner?.deliverEntered()
        return []  // We don't accept drops — DropZonePanel handles that.
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        owner?.deliverExited()
    }
}
