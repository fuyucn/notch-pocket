import SwiftUI

@MainActor
public struct ShelfListView: View {
    public let items: [ShelfItem]
    public let onOpen: (ShelfItem) -> Void
    public let onRemove: (UUID) -> Void

    public init(items: [ShelfItem], onOpen: @escaping (ShelfItem) -> Void, onRemove: @escaping (UUID) -> Void) {
        self.items = items
        self.onOpen = onOpen
        self.onRemove = onRemove
    }

    public var sortedItems: [ShelfItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }

    public var body: some View {
        if items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "tray")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
                Text("No files on the shelf")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedItems) { item in
                        ShelfListRowView(
                            item: item,
                            onOpen: { onOpen(item) },
                            onRemove: { onRemove(item.id) }
                        )
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }
}
