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
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            if items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Drop files here")
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
                    .padding(6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
