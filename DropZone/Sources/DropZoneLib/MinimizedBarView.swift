import SwiftUI

/// Minimized capsule view: a black horizontal pill whose middle is reserved
/// for the physical notch. The left shoulder shows a tray icon, the right
/// shoulder shows the current shelf count. Tap anywhere on the capsule to
/// request .opened.
@MainActor
public struct MinimizedBarView: View {
    public let shelfCount: Int
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let onTap: () -> Void

    public static let height: CGFloat = 32
    public static let shoulderWidth: CGFloat = 52

    public init(
        shelfCount: Int,
        notchWidth: CGFloat,
        notchHeight: CGFloat = Self.height,
        onTap: @escaping () -> Void
    ) {
        self.shelfCount = shelfCount
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.onTap = onTap
    }

    public var body: some View {
        // Scale text/icon + shoulder width proportionally to the capsule
        // height so the layout feels right whether we're on a 32pt MBP
        // notch or a 24pt external menu bar.
        let fontSize = notchHeight * 0.34
        let badgeHPad = notchHeight * 0.22
        let badgeVPad = notchHeight * 0.06
        let shoulderW = notchHeight * 1.2    // ~38pt @ 32pt, ~29pt @ 24pt
        HStack(spacing: 0) {
            // Left shoulder
            HStack(spacing: 4) {
                Image(systemName: "tray.fill")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: shoulderW, height: notchHeight)

            // Notch gap — reserved transparent space the physical notch sits over.
            Color.clear.frame(width: notchWidth, height: notchHeight)

            // Right shoulder
            HStack(spacing: 0) {
                Text("\(shelfCount)")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, badgeHPad)
                    .padding(.vertical, badgeVPad)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .frame(width: shoulderW, height: notchHeight)
        }
        .frame(height: notchHeight)
        .background(
            RoundedRectangle(cornerRadius: notchHeight / 2, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: notchHeight / 2, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
