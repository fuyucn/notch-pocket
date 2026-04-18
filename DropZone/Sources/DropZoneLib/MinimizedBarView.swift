import SwiftUI

/// Minimized capsule view: a black horizontal pill whose middle is reserved
/// for the physical notch. The left shoulder shows a tray icon, the right
/// shoulder shows the current shelf count. Tap anywhere on the capsule to
/// request .opened.
@MainActor
public struct MinimizedBarView: View {
    public let shelfCount: Int
    public let notchWidth: CGFloat
    public let onTap: () -> Void

    public static let height: CGFloat = 32
    public static let shoulderWidth: CGFloat = 52

    public init(shelfCount: Int, notchWidth: CGFloat, onTap: @escaping () -> Void) {
        self.shelfCount = shelfCount
        self.notchWidth = notchWidth
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left shoulder
            HStack(spacing: 4) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: Self.shoulderWidth, height: Self.height)

            // Notch gap — reserved transparent space the physical notch sits over.
            Color.clear.frame(width: notchWidth, height: Self.height)

            // Right shoulder
            HStack(spacing: 0) {
                Text("\(shelfCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .frame(width: Self.shoulderWidth, height: Self.height)
        }
        .frame(height: Self.height)
        .background(
            // Rounded capsule. The middle is clear anyway; the shape is purely
            // visual polish for the two shoulders.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
