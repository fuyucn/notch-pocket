import SwiftUI

/// Narrow bar shown while a drag hovers the pre-activation zone.
/// Final UI (icon + filename + shelf badge) lands in Task 7 — this stub just
/// shows the filename so `DropZonePanel` can host it now.
public struct PreActivationBarView: View {
    public let primaryFileName: String?
    public let extraCount: Int
    public let shelfCount: Int
    /// Vertical inset applied at the top so the content sits below the physical
    /// notch cutout (notch height + small padding). Defaults to 40 for previews.
    public let notchInset: CGFloat

    public static let empty = PreActivationBarView(primaryFileName: nil, extraCount: 0, shelfCount: 0)

    public init(primaryFileName: String?, extraCount: Int, shelfCount: Int, notchInset: CGFloat = 40) {
        self.primaryFileName = primaryFileName
        self.extraCount = extraCount
        self.shelfCount = shelfCount
        self.notchInset = notchInset
    }

    public var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: notchInset)   // sit below the physical notch cutout
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text("Drop here")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            if let name = primaryFileName {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 340)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}
