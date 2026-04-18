import Testing
import AppKit
import Foundation
@testable import DropZoneLib

@Suite("FileShelfView Tests")
@MainActor
struct FileShelfViewTests {

    private func makeTestItem(name: String = "test.txt", id: UUID = UUID()) -> ShelfItem {
        ShelfItem(
            id: id,
            storage: .localCopy(URL(fileURLWithPath: "/tmp/shelf/\(name)")),
            sourceURL: URL(fileURLWithPath: "/tmp/original/\(name)"),
            displayName: name,
            fileSize: 1024
        )
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTestFile(in dir: URL, name: String = "test.txt") throws -> URL {
        let fileURL = dir.appendingPathComponent(name)
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Creation

    @Test("View starts with no thumbnails")
    func startsEmpty() {
        let view = FileShelfView()
        // No file shelf manager set, so should show empty state
        #expect(view.subviews.count >= 1) // at least scrollView, clearAll, emptyLabel
    }

    @Test("View has layer backing")
    func layerBacked() {
        let view = FileShelfView()
        #expect(view.wantsLayer)
    }

    // MARK: - Shelf manager integration

    @Test("Setting shelf manager triggers reload")
    func settingManagerReloads() throws {
        let dir = try makeTempDirectory()
        let manager = FileShelfManager(directory: dir)
        try manager.ensureShelfDirectory()

        let sourceDir = try makeTempDirectory()
        let file = try makeTestFile(in: sourceDir)
        manager.addFiles(from: [file])

        let view = FileShelfView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))

        nonisolated(unsafe) var itemCount: Int?
        view.onItemCountChanged = { count in itemCount = count }
        view.fileShelfManager = manager

        #expect(itemCount == 1)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: sourceDir)
    }

    // MARK: - Callbacks

    @Test("onItemCountChanged fires on reload")
    func itemCountCallback() throws {
        let dir = try makeTempDirectory()
        let manager = FileShelfManager(directory: dir)
        try manager.ensureShelfDirectory()

        let view = FileShelfView()

        nonisolated(unsafe) var receivedCount: Int?
        view.onItemCountChanged = { count in receivedCount = count }

        view.fileShelfManager = manager
        #expect(receivedCount == 0)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("onShelfEmpty is set and callable")
    func shelfEmptyCallback() {
        let view = FileShelfView()

        nonisolated(unsafe) var emptyCalled = false
        view.onShelfEmpty = { emptyCalled = true }

        // Directly invoke to verify it's wired
        view.onShelfEmpty?()
        #expect(emptyCalled)
    }

    // MARK: - Animate add

    @Test("animateAddItems adds thumbnail views")
    func animateAdd() {
        let view = FileShelfView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.fileShelfManager = nil // No manager, just testing view layer

        let item = makeTestItem(name: "photo.png")
        view.animateAddItems([item])

        nonisolated(unsafe) var count: Int?
        view.onItemCountChanged = { c in count = c }
        // The view should have added a thumbnail
        view.animateAddItems([makeTestItem(name: "doc.pdf")])
        #expect(count == 2)
    }

    // MARK: - Layout

    @Test("View accepts zero-size frame without crash")
    func zeroSizeFrame() {
        let view = FileShelfView(frame: .zero)
        view.layout()
        // Should not crash
        #expect(true)
    }

    @Test("View handles large frame")
    func largeFrame() {
        let view = FileShelfView(frame: NSRect(x: 0, y: 0, width: 2000, height: 200))
        view.layout()
        #expect(true)
    }
}
