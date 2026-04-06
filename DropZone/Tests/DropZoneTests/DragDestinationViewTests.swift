import Testing
import AppKit
@testable import DropZoneLib

@Suite("DragDestinationView Tests")
@MainActor
struct DragDestinationViewTests {

    // MARK: - Creation

    @Test("View can be created with default frame")
    func creation() {
        let view = DragDestinationView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        #expect(view.frame.size.width == 320)
        #expect(view.frame.size.height == 80)
    }

    @Test("View wants layer")
    func wantsLayer() {
        let view = DragDestinationView(frame: .zero)
        #expect(view.wantsLayer)
    }

    @Test("View starts not highlighted")
    func startsNotHighlighted() {
        let view = DragDestinationView(frame: .zero)
        #expect(!view.isHighlighted)
    }

    @Test("View starts with zero drag item count")
    func startsWithZeroDragCount() {
        let view = DragDestinationView(frame: .zero)
        #expect(view.dragItemCount == 0)
    }

    // MARK: - Dependencies

    @Test("fileShelfManager is nil by default")
    func noManagerByDefault() {
        let view = DragDestinationView(frame: .zero)
        #expect(view.fileShelfManager == nil)
    }

    @Test("fileShelfManager can be set")
    func setManager() throws {
        let view = DragDestinationView(frame: .zero)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragViewTest-\(UUID().uuidString)", isDirectory: true)
        let manager = FileShelfManager(directory: dir)
        view.fileShelfManager = manager
        #expect(view.fileShelfManager != nil)
    }

    // MARK: - Callbacks

    @Test("Callbacks are nil by default")
    func callbacksNilByDefault() {
        let view = DragDestinationView(frame: .zero)
        #expect(view.onDragEntered == nil)
        #expect(view.onDragExited == nil)
        #expect(view.onFilesDropped == nil)
    }

    @Test("Callbacks can be set")
    func callbacksSettable() {
        let view = DragDestinationView(frame: .zero)
        view.onDragEntered = {}
        view.onDragExited = {}
        view.onFilesDropped = { _ in }
        #expect(view.onDragEntered != nil)
        #expect(view.onDragExited != nil)
        #expect(view.onFilesDropped != nil)
    }

    // MARK: - Registered types

    @Test("View registers for drag types")
    func registeredForDragTypes() {
        let view = DragDestinationView(frame: .zero)
        // The view should have registered drag types during init.
        // We verify it has been set up by checking registeredDraggedTypes.
        let types = view.registeredDraggedTypes
        #expect(types.contains(.fileURL))
    }
}

@Suite("ShelfItem Tests")
struct ShelfItemTests {

    @Test("ShelfItem creation with all fields")
    func creation() {
        let id = UUID()
        let now = Date()
        let item = ShelfItem(
            id: id,
            originalURL: URL(fileURLWithPath: "/tmp/source.txt"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/dest.txt"),
            displayName: "source.txt",
            addedAt: now,
            fileSize: 1024
        )
        #expect(item.id == id)
        #expect(item.displayName == "source.txt")
        #expect(item.fileSize == 1024)
        #expect(item.addedAt == now)
    }

    @Test("ShelfItem defaults generate unique IDs")
    func uniqueIDs() {
        let item1 = ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/a.txt"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/a.txt"),
            displayName: "a.txt",
            fileSize: 0
        )
        let item2 = ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/b.txt"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/b.txt"),
            displayName: "b.txt",
            fileSize: 0
        )
        #expect(item1.id != item2.id)
    }
}
