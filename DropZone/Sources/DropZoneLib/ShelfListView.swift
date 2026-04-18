import SwiftUI

@MainActor
public struct ShelfListView: View {
    public let items: [ShelfItem]
    public let isDragInside: Bool
    public let removeOnDragOut: Bool
    public let onOpen: (ShelfItem) -> Void
    public let onRemove: (UUID) -> Void
    public let onRemoveAll: () -> Void

    public init(
        items: [ShelfItem],
        isDragInside: Bool = false,
        removeOnDragOut: Bool = true,
        onOpen: @escaping (ShelfItem) -> Void,
        onRemove: @escaping (UUID) -> Void,
        onRemoveAll: @escaping () -> Void = {}
    ) {
        self.items = items
        self.isDragInside = isDragInside
        self.removeOnDragOut = removeOnDragOut
        self.onOpen = onOpen
        self.onRemove = onRemove
        self.onRemoveAll = onRemoveAll
    }

    public var sortedItems: [ShelfItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDragInside ? Color.white.opacity(0.06) : Color.clear)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDragInside ? Color.white.opacity(0.75) : Color.white.opacity(0.25),
                    style: StrokeStyle(
                        lineWidth: isDragInside ? 1.5 : 1,
                        dash: isDragInside ? [] : [4, 3]
                    )
                )
            ScrollView {
                LazyVStack(spacing: 0) {
                    if sortedItems.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ForEach(sortedItems) { item in
                            ShelfListRowView(
                                item: item,
                                removeOnDragOut: removeOnDragOut,
                                onOpen: { onOpen(item) },
                                onRemove: { onRemove(item.id) }
                            )
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
                .padding(6)
            }
            if !sortedItems.isEmpty {
                AllDragHandle(
                    items: sortedItems,
                    onAllDelivered: { if removeOnDragOut { onRemoveAll() } }
                )
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.15), value: isDragInside)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.4))
            Text("Drop files here")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
