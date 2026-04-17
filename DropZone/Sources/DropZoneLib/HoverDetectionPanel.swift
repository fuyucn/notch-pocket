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
        // Use the pre-activation rect for the detection area (activation zone + 8px hysteresis outset).
        let rect = geometry.preActivationRect
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
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

        setFrame(rect, display: false)
        orderFrontRegardless()
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        setFrame(geometry.preActivationRect, display: true)
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { owner?.deliverEntered() }
    override func mouseExited(with event: NSEvent) { owner?.deliverExited() }
}
