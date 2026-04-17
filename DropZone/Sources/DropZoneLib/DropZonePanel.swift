import AppKit
import SwiftUI

/// The visual state of the DropZone panel (maps to DESIGN.md state machine).
public enum PanelState: Sendable {
    case hidden
    case listening      // Invisible, waiting for drag to enter activation zone
    case preActivated   // Drag entered the outer pre-activation rect (narrow bar visible)
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

    private static let expandDuration: TimeInterval = 0.35
    private static let collapseDuration: TimeInterval = 0.25
    private static let springDamping: CGFloat = 0.75

    // MARK: - Visual effect

    private let blurView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = NotchGeometry.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        view.layer?.masksToBounds = true
        return view
    }()

    // MARK: - Drag destination

    /// The drag destination view that handles NSDraggingDestination.
    public let dragDestinationView = DragDestinationView()

    // MARK: - Shelf view

    /// The file shelf view showing thumbnails of shelved files.
    public let fileShelfView = FileShelfView()

    // MARK: - Pre-activation bar

    /// SwiftUI host for the narrow pre-activation bar.
    public let preActivationBarHost = NSHostingView(rootView: PreActivationBarView.empty)

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
        // Use popUpMenu level — high enough to float above most windows,
        // but low enough that system drag sessions can still target us.
        // CGShieldingWindowLevel is too high and blocks drag-and-drop.
        level = .popUpMenu
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // We use a custom shadow layer instead
        ignoresMouseEvents = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        animationBehavior = .none
    }

    private func configureVisualContent() {
        guard let contentView else { return }
        contentView.wantsLayer = true

        // Custom shadow on content view layer for soft, notch-like glow
        if let layer = contentView.layer {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.4
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: -4)
            layer.masksToBounds = false
        }

        blurView.frame = contentView.bounds
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        // Add file shelf view (hidden by default, shown only in shelfExpanded state)
        fileShelfView.frame = contentView.bounds
        fileShelfView.autoresizingMask = [.width, .height]
        fileShelfView.isHidden = true
        contentView.addSubview(fileShelfView)

        // Add pre-activation bar (hidden by default, shown only in preActivated state)
        preActivationBarHost.frame = contentView.bounds
        preActivationBarHost.autoresizingMask = [.width, .height]
        preActivationBarHost.isHidden = true
        contentView.addSubview(preActivationBarHost)

        // Add drag destination view on top — must be topmost to receive drag events
        dragDestinationView.frame = contentView.bounds
        dragDestinationView.autoresizingMask = [.width, .height]
        contentView.addSubview(dragDestinationView)
    }

    // MARK: - NSPanel overrides

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    // MARK: - State transitions

    /// Transition to the expanded (drop zone visible) state.
    public func expand() {
        guard panelState != .expanded else { return }
        panelState = .expanded

        // Keep shelf hidden during drop-zone mode — only dragDestinationView should be active
        fileShelfView.isHidden = true
        preActivationBarHost.isHidden = true

        let targetSize = NotchGeometry.preActivatedSize
        let targetOrigin = geometry.panelOrigin(for: targetSize)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)

        // Start small and transparent for a Dynamic Island-like pop
        alphaValue = 0
        setFrame(targetFrame.insetBy(dx: 20, dy: 8), display: false)
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true

            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }

        // Ensure frame is at target size regardless of animation completion (important for tests)
        setFrame(targetFrame, display: false)
    }

    /// Expand the panel to show the file shelf with thumbnails.
    public func expandShelf() {
        guard panelState != .shelfExpanded else { return }
        panelState = .shelfExpanded

        fileShelfView.isHidden = false
        hideBadge()

        let targetSize = NotchGeometry.shelfExpandedSize
        let targetOrigin = geometry.panelOrigin(for: targetSize)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)

        if !isVisible {
            alphaValue = 0
            // Start slightly smaller for a smooth pop-in
            setFrame(targetFrame.insetBy(dx: 15, dy: 6), display: false)
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
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

        // Shrink toward the notch center for a natural collapse effect
        let currentFrame = frame
        let collapsedFrame = currentFrame.insetBy(dx: 20, dy: 8)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.collapseDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.68, 0.3)
            context.allowsImplicitAnimation = true

            self.animator().setFrame(collapsedFrame, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.orderOut(nil)
                self?.panelState = .hidden
                self?.fileShelfView.isHidden = true
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

    /// Enter the pre-activated (narrow bar) state from `.listening`.
    public func enterPreActivation(primaryFileName: String?, extraCount: Int, shelfCount: Int) {
        guard panelState == .listening || panelState == .preActivated else { return }

        preActivationBarHost.rootView = PreActivationBarView(
            primaryFileName: primaryFileName,
            extraCount: max(0, extraCount),
            shelfCount: max(0, shelfCount)
        )
        preActivationBarHost.isHidden = false

        panelState = .preActivated

        let targetSize = NotchGeometry.preActivatedSize
        let targetOrigin = geometry.panelOrigin(for: targetSize)
        let targetFrame = NSRect(origin: targetOrigin, size: targetSize)

        if !isVisible {
            alphaValue = 0
            setFrame(targetFrame.insetBy(dx: 15, dy: 6), display: false)
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.expandDuration * 0.6
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }

        // Ensure frame is at target size regardless of animation completion (important for tests)
        setFrame(targetFrame, display: false)
    }

    /// Leave pre-activated state.
    public func exitPreActivation() {
        guard panelState == .preActivated else { return }
        preActivationBarHost.isHidden = true
        panelState = .listening
        if isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.collapseDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.orderOut(nil)
                }
            })
        }
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

    // MARK: - Mouse hover tracking

    private var trackingArea: NSTrackingArea?

    /// Set up a tracking area over the activation zone to detect mouse hover.
    /// When the user hovers over the notch area and files are on the shelf,
    /// the panel expands to show the shelf.
    public func setupHoverTracking() {
        guard let contentView else { return }
        if let existing = trackingArea {
            contentView.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        trackingArea = area
    }

    /// Callback when mouse hovers over the panel (for shelf reveal).
    public var onMouseEntered: (@MainActor () -> Void)?
    /// Callback when mouse leaves the panel.
    public var onMouseExited: (@MainActor () -> Void)?

    public override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    public override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    // MARK: - Repositioning

    /// Update frame to match current geometry and state.
    public func repositionForCurrentState() {
        switch panelState {
        case .hidden, .listening, .collapsed:
            // No visible change needed
            break
        case .preActivated:
            let targetSize = NotchGeometry.preActivatedSize
            let targetOrigin = geometry.panelOrigin(for: targetSize)
            setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
        case .expanded:
            let targetSize = NotchGeometry.preActivatedSize
            let targetOrigin = geometry.panelOrigin(for: targetSize)
            setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
        case .shelfExpanded:
            let targetSize = NotchGeometry.shelfExpandedSize
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
