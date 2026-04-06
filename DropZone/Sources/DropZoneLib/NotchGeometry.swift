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
    public static let activationPaddingBottom: CGFloat = 40
    /// Horizontal padding on each side of the notch for the activation zone.
    public static let activationPaddingSide: CGFloat = 20

    /// Default panel size for the collapsed notch indicator (no-notch fallback).
    public static let fallbackPillSize = NSSize(width: 200, height: 32)
    /// Expanded drop zone size.
    public static let expandedSize = NSSize(width: 320, height: 80)
    /// Corner radius matching the notch shape.
    public static let cornerRadius: CGFloat = 18

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

    /// The origin point for the DropZonePanel in its collapsed state.
    /// Centered horizontally on the notch (or screen top), flush with top.
    public func panelOrigin(for size: NSSize) -> NSPoint {
        let centerX: CGFloat
        let topY: CGFloat

        if let notch = notchRect {
            centerX = notch.midX
            topY = notch.minY // Panel grows downward from notch bottom
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

    // MARK: - Private

    private static func expandedActivationZone(around rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x - activationPaddingSide,
            y: rect.origin.y - activationPaddingBottom,
            width: rect.width + activationPaddingSide * 2,
            height: rect.height + activationPaddingBottom
        )
    }
}
