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
        // Let clicks pass through to windows below; tracking areas and
        // NSDraggingDestination still work independently of this flag.
        ignoresMouseEvents = true
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
}

@MainActor
private final class HoverTrackingView: NSView {
    weak var owner: HoverDetectionPanel?
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        // Tracking areas fire regardless of `window.ignoresMouseEvents`,
        // so we still get entered/exited for bare hover.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // Route clicks through — hit-test negative means the window doesn't
    // intercept them, so the app below receives them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { owner?.deliverEntered() }
    override func mouseExited(with event: NSEvent) { owner?.deliverExited() }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        owner?.deliverEntered()
        return []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        owner?.deliverExited()
    }
}
