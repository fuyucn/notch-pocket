import AppKit

/// Delegate for hover events delivered by the HoverDetectionPanel.
@MainActor
public protocol HoverDetectionDelegate: AnyObject {
    func hoverEntered()
    func hoverExited()
}

/// Invisible, click-through NSPanel pinned at notch top whose only job is to
/// deliver drag-hover events to a delegate via NSDraggingDestination.
/// No global event monitors — no TCC permission required.
@MainActor
public final class HoverDetectionPanel: NSPanel {
    public weak var hoverDelegate: HoverDetectionDelegate?

    private let trackingView = HoverTrackingView()

    public init(geometry: NotchGeometry) {
        let rect = geometry.hoverTriggerRect
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false // We need draggingEntered/draggingExited
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        trackingView.owner = self
        contentView = trackingView

        setFrame(geometry.hoverTriggerRect, display: false)
        orderFrontRegardless()
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        setFrame(geometry.hoverTriggerRect, display: true)
    }

    // Delegate invocation helpers called by the tracking view
    fileprivate func deliverEntered() { hoverDelegate?.hoverEntered() }
    fileprivate func deliverExited() { hoverDelegate?.hoverExited() }

    // We never want this panel to steal keyboard focus.
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    // Pass all events through to what's underneath — we only care about drag events.
    // Drag events are handled by HoverTrackingView as NSDraggingDestination.
    override public func sendEvent(_ event: NSEvent) { }
}

@MainActor
private final class HoverTrackingView: NSView {
    weak var owner: HoverDetectionPanel?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        owner?.deliverEntered()
        return []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        owner?.deliverExited()
    }
}
