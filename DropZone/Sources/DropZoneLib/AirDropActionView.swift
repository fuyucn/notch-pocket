import SwiftUI
import AppKit

@MainActor
public struct AirDropActionView: View {
    public let isEnabled: Bool
    /// Target side length. The view renders as a square of this size.
    public let size: CGFloat
    public let isDropTargeted: Bool
    public let onTap: () -> Void
    /// Invoked with the AirDrop button's frame in the panel's content-view
    /// coordinates whenever SwiftUI reports a new layout. `NotchDropForwarder`
    /// uses this to steer drops on the AirDrop region to AirDrop instead of
    /// the shelf.
    public let onFrameChange: (CGRect) -> Void

    public init(
        isEnabled: Bool,
        size: CGFloat = 86,
        isDropTargeted: Bool = false,
        onTap: @escaping () -> Void,
        onFrameChange: @escaping (CGRect) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.size = size
        self.isDropTargeted = isDropTargeted
        self.onTap = onTap
        self.onFrameChange = onFrameChange
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.forward")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                Text("AirDrop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.34, blue: 0.36)
                        .opacity(isEnabled ? (isDropTargeted ? 1.0 : 0.90) : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.white.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
            .background(
                GeometryReader { proxy -> Color in
                    let rect = proxy.frame(in: .global)
                    Task { @MainActor in onFrameChange(rect) }
                    return Color.clear
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }
}
