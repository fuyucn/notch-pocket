import Testing
@testable import DropZoneLib

@MainActor
struct ShelfHeaderViewTests {
    @Test
    func titlePluralizes() {
        let h = ShelfHeaderView(itemCount: 3, viewMode: .list, onToggleView: {}, onMinimize: {})
        #expect(h.titleLabel == "3 items")
    }

    @Test
    func titleSingular() {
        let h = ShelfHeaderView(itemCount: 1, viewMode: .list, onToggleView: {}, onMinimize: {})
        #expect(h.titleLabel == "1 item")
    }

    @Test
    func zeroItems() {
        let h = ShelfHeaderView(itemCount: 0, viewMode: .list, onToggleView: {}, onMinimize: {})
        #expect(h.titleLabel == "0 items")
    }
}
