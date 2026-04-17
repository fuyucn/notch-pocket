import Testing
import Foundation
@testable import DropZoneLib

@MainActor
struct ShelfGridViewTests {
    private func item(_ name: String, added: Date = Date(), ext: String? = "txt") -> ShelfItem {
        ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/\(name)"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/\(name)"),
            displayName: name,
            addedAt: added,
            fileSize: 100,
            sourceAppName: "Finder",
            fileExtension: ext
        )
    }

    @Test
    func sortsNewestFirst() {
        let older = item("a.txt", added: Date(timeIntervalSince1970: 1000))
        let newer = item("b.txt", added: Date(timeIntervalSince1970: 2000))
        let view = ShelfGridView(items: [older, newer], onOpen: { _ in }, onRemove: { _ in })
        #expect(view.sortedItems.map(\.displayName) == ["b.txt", "a.txt"])
    }

    @Test
    func emptyItemsStoresEmptyList() {
        let view = ShelfGridView(items: [], onOpen: { _ in }, onRemove: { _ in })
        #expect(view.items.isEmpty)
    }
}
