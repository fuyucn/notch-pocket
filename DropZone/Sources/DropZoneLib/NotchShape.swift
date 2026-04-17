// NotchShape.swift
// Adapted from Octane0411/open-vibe-island (MIT License)
// https://github.com/Octane0411/open-vibe-island/blob/main/Sources/OpenIslandApp/NotchShape.swift

import SwiftUI

/// A shape that mimics macOS Dynamic-Island geometry: top corners are concave
/// (curving inward into the physical notch), bottom corners are standard
/// rounded corners. Animates smoothly between radii pairs.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 4)
        let botR = min(bottomCornerRadius, rect.width / 4, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left concave curve (inward)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

        // Top-right concave curve (inward)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
    }
}

extension NotchShape {
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 20
    static let openedTopRadius: CGFloat = 22
    static let openedBottomRadius: CGFloat = 36

    static var closed: NotchShape {
        NotchShape(topCornerRadius: closedTopRadius, bottomCornerRadius: closedBottomRadius)
    }

    static var opened: NotchShape {
        NotchShape(topCornerRadius: openedTopRadius, bottomCornerRadius: openedBottomRadius)
    }
}
