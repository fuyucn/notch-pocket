import AppKit

/// Geometry calculations for notch detection and activation zones.
public struct NotchGeometry: Sendable {
    /// The notch rectangle in screen coordinates (if the screen has a notch).
    public let notchRect: NSRect?
    /// The activation zone: notch expanded by padding for easier targeting.
    public let activationZone: NSRect
    /// The screen this geometry was computed for.
    public let screenFrame: NSRect
    /// Whether this screen has a hardware notch.
    public let hasNotch: Bool

    // MARK: - Design constants

    /// Vertical padding below the notch for the activation zone.
    public static let activationPaddingBottom: CGFloat = 60
    /// Vertical padding above the notch to extend activation zone to screen edge.
    public static let activationPaddingTop: CGFloat = 10
    /// Horizontal padding on each side of the notch for the activation zone.
    public static let activationPaddingSide: CGFloat = 30

    /// Default panel size for the collapsed notch indicator (no-notch fallback).
    public static let fallbackPillSize = NSSize(width: 200, height: 32)
    /// Expanded drop zone size.
    public static let expandedSize = NSSize(width: 320, height: 80)
    /// Narrow pre-activation bar displayed when the cursor enters the pre-activation zone.
    public static let preActivatedSize = NSSize(width: 380, height: 120)
    /// Full shelf panel size (list view / thumbnail view).
    public static let shelfExpandedSize = NSSize(width: 560, height: 150)
    /// Hysteresis outset (px) between the pre-activation rect and the activation zone.
    public static let preActivationOutset: CGFloat = 8
    /// Corner radius matching the notch shape.
    public static let cornerRadius: CGFloat = 18
    /// Horizontal padding on each side of the notch used by the popping/opened
    /// panel shape. Makes the panel visibly "wrap" the notch.
    public static let sidePadding: CGFloat = 80

    // MARK: - Computed panel sizes

    /// Panel size in the popping (pre-activation) state.
    /// Width = notch + sidePadding*2, height = matches existing preActivatedSize.height.
    public var preActivatedPanelSize: NSSize {
        let notchWidth = notchRect?.width ?? 200
        return NSSize(
            width: notchWidth + Self.sidePadding * 2,
            height: Self.preActivatedSize.height
        )
    }

    /// Panel size in the opened state. Wider than popping to fit shelf content.
    /// Width = notch + sidePadding * 4 (default 520 for 200-wide notch),
    /// height = matches shelfExpandedSize.height (compact Dynamic Island feel).
    public var openedPanelSize: NSSize {
        let notchWidth = notchRect?.width ?? 200
        return NSSize(
            width: notchWidth + Self.sidePadding * 4,
            height: Self.shelfExpandedSize.height
        )
    }

    // MARK: - Init

    /// Compute geometry for the given screen.
    public init(screen: NSScreen) {
        self.screenFrame = screen.frame

        if screen.safeAreaInsets.top != 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Screen has a notch — compute notch rect from auxiliary areas
            let rect = NSRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.safeAreaInsets.top,
                width: right.minX - left.maxX,
                height: screen.safeAreaInsets.top
            )
            self.notchRect = rect
            self.hasNotch = true
            self.activationZone = Self.expandedActivationZone(around: rect)
        } else {
            // No notch — use a centered pill at top of screen
            self.notchRect = nil
            self.hasNotch = false
            let pillOrigin = NSPoint(
                x: screen.frame.midX - Self.fallbackPillSize.width / 2,
                y: screen.frame.maxY - Self.fallbackPillSize.height
            )
            let pillRect = NSRect(origin: pillOrigin, size: Self.fallbackPillSize)
            self.activationZone = Self.expandedActivationZone(around: pillRect)
        }
    }

    /// Create geometry with explicit values (for testing).
    public init(notchRect: NSRect?, activationZone: NSRect, screenFrame: NSRect, hasNotch: Bool) {
        self.notchRect = notchRect
        self.activationZone = activationZone
        self.screenFrame = screenFrame
        self.hasNotch = hasNotch
    }

    // MARK: - Panel positioning

    /// The origin point for the DropZonePanel.
    /// Centered horizontally on the notch (or screen top).
    /// The panel's top edge aligns with the top of the screen (notch top),
    /// expanding downward like a Dynamic Island.
    public func panelOrigin(for size: NSSize) -> NSPoint {
        let centerX: CGFloat
        let topY: CGFloat

        if let notch = notchRect {
            centerX = notch.midX
            // Panel top aligns with screen top (notch top edge) and grows downward
            topY = notch.maxY
        } else {
            centerX = screenFrame.midX
            topY = screenFrame.maxY
        }

        return NSPoint(
            x: centerX - size.width / 2,
            y: topY - size.height
        )
    }

    /// Whether a point (in screen coordinates) is inside the activation zone.
    public func containsPoint(_ point: NSPoint) -> Bool {
        activationZone.contains(point)
    }

    /// The pre-activation rect = `activationZone` grown by `preActivationOutset` on every side.
    /// The drag enters pre-activation when the cursor crosses this outer rect; it exits only
    /// when the cursor leaves `activationZone` proper (providing hysteresis against flicker).
    public var preActivationRect: NSRect {
        activationZone.insetBy(dx: -Self.preActivationOutset, dy: -Self.preActivationOutset)
    }

    /// Large rect covering the top of the screen used by NotchPanel. Includes the
    /// notch/menu-bar row so the panel can be anchored flush to the top of the
    /// screen and visually wrap the notch like a Dynamic Island.
    public var hoverTriggerRect: NSRect {
        let width = screenFrame.width * 0.5
        let height: CGFloat = 200
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height   // top-anchored
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Private

    private static func expandedActivationZone(around rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x - activationPaddingSide,
            y: rect.origin.y - activationPaddingBottom,
            width: rect.width + activationPaddingSide * 2,
            height: rect.height + activationPaddingBottom + activationPaddingTop
        )
    }
}
