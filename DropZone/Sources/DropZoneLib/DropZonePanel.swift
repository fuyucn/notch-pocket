import AppKit

/// The visual state of the DropZone panel (maps to DESIGN.md state machine).
public enum PanelState: Sendable {
    case hidden
    case listening      // Invisible, waiting for drag to enter activation zone
    case expanded       // Drop zone visible, accepting drops
    case shelfExpanded  // Shelf UI visible, showing thumbnails (after drop or click)
    case collapsed      // Collapsing back after drag leaves without drop
}

/// A borderless, floating NSPanel that overlays the notch area.
/// Handles positioning, show/hide animations, and the Dynamic Island
/// expand/collapse effect.
@MainActor
public final class DropZonePanel: NSPanel {
    // MARK: - State

    public private(set) var panelState: PanelState = .hidden
    public var geometry: NotchGeometry {
        didSet { repositionForCurrentState() }
    }

    // MARK: - Animation constants (from DESIGN.md)

    private static let expandDuration: TimeInterval = 0.3
    private static let collapseDuration: TimeInterval = 0.25
    private static let springDamping: CGFloat = 0.75
    // Spring response mapped to CA timing: use damped spring or ease-out approximation

    // MARK: - Visual effect

    private let blurView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = NotchGeometry.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        view.layer?.masksToBounds = true
        return view
    }()

    // MARK: - Drag destination

    /// The drag destination view that handles NSDraggingDestination.
    public let dragDestinationView = DragDestinationView()

    // MARK: - Shelf view

    /// The file shelf view showing thumbnails of shelved files.
    public let fileShelfView = FileShelfView()

    // MARK: - File count badge

    /// Badge layer showing the number of files on the shelf when collapsed.
    private var countBadgeLayer: CATextLayer?

    // MARK: - Init

    public init(geometry: NotchGeometry) {
        self.geometry = geometry

        // Start with collapsed size at the notch position
        let collapsedSize = geometry.hasNotch
            ? (geometry.notchRect?.size ?? NotchGeometry.fallbackPillSize)
            : NotchGeometry.fallbackPillSize
        let origin = geometry.panelOrigin(for: collapsedSize)
        let frame = NSRect(origin: origin, size: collapsedSize)

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        configurePanelBehavior()
        configureVisualContent()
    }

    // MARK: - Panel configuration

    private func configurePanelBehavior() {
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        animationBehavior = .none
    }

    private func configureVisualContent() {
        guard let contentView else { return }
        blurView.frame = contentView.bounds
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        // Add drag destination view on top of blur
        dragDestinationView.frame = contentView.bounds
        dragDestinationView.autoresizingMask = [.width, .height]
        contentView.addSubview(dragDestinationView)

        // Add file shelf view on top of drag destination
        fileShelfView.frame = contentView.bounds
        fileShelfView.autoresizingMask = [.width, .height]
        contentView.addSubview(fileShelfView)
    }

    // MARK: - NSPanel overrides

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    // MARK: - Shelf expanded size

    /// Size of the panel when showing the file shelf with thumbnails.
    public static let shelfExpandedSize = NSSize(width: 420, height: 100)

    // MARK: - State transitions

    /// Transition to the expanded (drop zone visible) state.
    public func expand() {
        guard panelState != .expanded else { return }
        panelState = .expanded

        fileShelfView.isHidden = false

        let targetSize = NotchGeometry.expandedSize
        let targetOrigin = geometry.panelOrigin(for: targetSize)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)

        // Make visible before animating
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0) // spring-like ease-out
            context.allowsImplicitAnimation = true

            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }
    }

    /// Expand the panel to show the file shelf with thumbnails.
    public func expandShelf() {
        guard panelState != .shelfExpanded else { return }
        panelState = .shelfExpanded

        fileShelfView.isHidden = false
        hideBadge()

        let targetSize = Self.shelfExpandedSize
        let targetOrigin = geometry.panelOrigin(for: targetSize)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)

        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            context.allowsImplicitAnimation = true

            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }
    }

    /// Collapse the panel back to hidden.
    public func collapse(completion: (@Sendable () -> Void)? = nil) {
        guard panelState == .expanded || panelState == .shelfExpanded else {
            completion?()
            return
        }
        panelState = .collapsed

        let collapsedSize = geometry.hasNotch
            ? (geometry.notchRect?.size ?? NotchGeometry.fallbackPillSize)
            : NotchGeometry.fallbackPillSize
        let collapsedOrigin = geometry.panelOrigin(for: collapsedSize)
        let collapsedFrame = NSRect(origin: collapsedOrigin, size: collapsedSize)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.collapseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            self.animator().setFrame(collapsedFrame, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.orderOut(nil)
                self?.panelState = .hidden
                completion?()
            }
        })
    }

    /// Enter listening state (invisible, ready to detect drag entering activation zone).
    public func enterListening() {
        guard panelState == .hidden else { return }
        panelState = .listening
        // Panel stays ordered out — we only track mouse/drag position
        // via ScreenDetector / global drag monitor
    }

    /// Return to hidden state.
    public func hide() {
        if isVisible {
            orderOut(nil)
        }
        alphaValue = 0
        panelState = .hidden
    }

    // MARK: - File count badge

    /// Show or update the file count badge on the collapsed panel.
    public func updateBadge(count: Int) {
        guard count > 0 else {
            hideBadge()
            return
        }

        guard let contentLayer = contentView?.layer else { return }

        if countBadgeLayer == nil {
            let badge = CATextLayer()
            badge.fontSize = 10
            badge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            badge.foregroundColor = NSColor.white.cgColor
            badge.backgroundColor = NSColor.systemRed.cgColor
            badge.cornerRadius = 8
            badge.alignmentMode = .center
            badge.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            badge.masksToBounds = true
            contentLayer.addSublayer(badge)
            countBadgeLayer = badge
        }

        guard let badge = countBadgeLayer else { return }
        let text = count > 99 ? "99+" : "\(count)"
        badge.string = text

        let textWidth = max(CGFloat(text.count) * 7 + 6, 16)
        let badgeSize = CGSize(width: textWidth, height: 16)
        badge.frame = CGRect(
            x: contentLayer.bounds.maxX - badgeSize.width - 4,
            y: contentLayer.bounds.maxY - badgeSize.height - 4,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }

    /// Hide the file count badge.
    public func hideBadge() {
        countBadgeLayer?.removeFromSuperlayer()
        countBadgeLayer = nil
    }

    // MARK: - Repositioning

    /// Update frame to match current geometry and state.
    public func repositionForCurrentState() {
        switch panelState {
        case .hidden, .listening, .collapsed:
            // No visible change needed
            break
        case .expanded:
            let targetSize = NotchGeometry.expandedSize
            let targetOrigin = geometry.panelOrigin(for: targetSize)
            setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
        case .shelfExpanded:
            let targetSize = Self.shelfExpandedSize
            let targetOrigin = geometry.panelOrigin(for: targetSize)
            setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
        }
    }

    // MARK: - Drop confirmation animation

    /// Play a brief scale pulse to confirm a successful drop.
    public func playDropConfirmation(completion: (() -> Void)? = nil) {
        guard let layer = contentView?.layer else {
            completion?()
            return
        }

        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1.0, 1.1, 1.0]
        pulse.keyTimes = [0, 0.4, 1.0]
        pulse.duration = 0.2
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion?()
        }
        layer.add(pulse, forKey: "dropConfirmation")
        CATransaction.commit()
    }
}
