import Testing
import AppKit
@testable import DropZoneLib

@Suite("FileThumbnailView Tests")
@MainActor
struct FileThumbnailViewTests {

    private func makeTestItem(name: String = "test.txt") -> ShelfItem {
        ShelfItem(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/original/\(name)"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/\(name)"),
            displayName: name,
            fileSize: 1024
        )
    }

    // MARK: - Creation

    @Test("View creates with correct item")
    func creation() {
        let item = makeTestItem()
        let view = FileThumbnailView(item: item)
        #expect(view.item.id == item.id)
        #expect(view.item.displayName == "test.txt")
    }

    @Test("View has expected size")
    func viewSize() {
        let view = FileThumbnailView(item: makeTestItem())
        let expectedSize = FileThumbnailView.itemSize
        #expect(view.frame.size.width == expectedSize.width)
        #expect(view.frame.size.height == expectedSize.height)
    }

    @Test("View has layer backing enabled")
    func layerBacked() {
        let view = FileThumbnailView(item: makeTestItem())
        #expect(view.wantsLayer)
    }

    // MARK: - Subviews

    @Test("View has image view, label, and remove button as subviews")
    func hasSubviews() {
        let view = FileThumbnailView(item: makeTestItem())
        // Should have at least 3 subviews: imageView, nameLabel, removeButton
        #expect(view.subviews.count >= 3)
    }

    @Test("Remove button is initially hidden")
    func removeButtonHidden() {
        let view = FileThumbnailView(item: makeTestItem())
        // The last subview should be the remove button
        let button = view.subviews.compactMap { $0 as? NSButton }.first
        #expect(button != nil)
        #expect(button?.isHidden == true)
    }

    // MARK: - Callbacks

    @Test("onRemove callback receives correct item ID")
    func onRemoveCallback() {
        let item = makeTestItem()
        let view = FileThumbnailView(item: item)

        nonisolated(unsafe) var receivedID: UUID?
        view.onRemove = { id in receivedID = id }

        // Simulate remove button click by sending action
        let button = view.subviews.compactMap { $0 as? NSButton }.first
        #expect(button != nil)
        button?.performClick(nil)
        #expect(receivedID == item.id)
    }

    // MARK: - Item size

    @Test("itemSize returns positive dimensions")
    func itemSizePositive() {
        let size = FileThumbnailView.itemSize
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    // MARK: - NSDraggingSource

    @Test("View conforms to NSDraggingSource")
    func isDraggingSource() {
        let view = FileThumbnailView(item: makeTestItem())
        // Verify it can provide source operation mask
        let mask = view.draggingSession(
            NSDraggingSession(),
            sourceOperationMaskFor: .outsideApplication
        )
        #expect(mask.contains(.copy))
    }

    @Test("Within-application drag returns move operation")
    func withinAppDragReturnsMove() {
        let view = FileThumbnailView(item: makeTestItem())
        let mask = view.draggingSession(
            NSDraggingSession(),
            sourceOperationMaskFor: .withinApplication
        )
        #expect(mask == .move)
    }
}
