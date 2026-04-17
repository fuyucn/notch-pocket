import SwiftUI

/// Narrow bar shown while a drag hovers the pre-activation zone.
/// Final UI (icon + filename + shelf badge) lands in Task 7 — this stub just
/// shows the filename so `DropZonePanel` can host it now.
public struct PreActivationBarView: View {
    public let primaryFileName: String?
    public let extraCount: Int
    public let shelfCount: Int

    public static let empty = PreActivationBarView(primaryFileName: nil, extraCount: 0, shelfCount: 0)

    public init(primaryFileName: String?, extraCount: Int, shelfCount: Int) {
        self.primaryFileName = primaryFileName
        self.extraCount = extraCount
        self.shelfCount = shelfCount
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text("Drop here")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            if let name = primaryFileName {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
