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
        Text(primaryFileName ?? "Dragging…")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
