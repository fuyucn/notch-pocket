import Testing
import Foundation
@testable import DropZoneLib

@Suite("FileShelfManager Tests")
@MainActor
struct FileShelfManagerTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropZoneTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTestFile(in dir: URL, name: String = "test.txt", content: String = "hello") throws -> URL {
        let fileURL = dir.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func makeManager(dir: URL? = nil) throws -> (FileShelfManager, URL) {
        let shelfDir = try dir ?? makeTempDirectory()
        let manager = FileShelfManager(directory: shelfDir)
        try manager.ensureShelfDirectory()
        return (manager, shelfDir)
    }

    // MARK: - Creation

    @Test("Manager starts with empty items")
    func startsEmpty() throws {
        let (manager, dir) = try makeManager()
        #expect(manager.items.isEmpty)
        #expect(manager.totalBytes == 0)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Default configuration values")
    func defaultConfig() throws {
        let (manager, dir) = try makeManager()
        #expect(manager.expiryInterval == 3600)
        #expect(manager.maxTotalBytes == 2_147_483_648)
        #expect(manager.maxItems == 50)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Adding files

    @Test("Add a single file")
    func addSingleFile() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)

        let added = manager.addFiles(from: [fileURL])
        #expect(added.count == 1)
        #expect(manager.items.count == 1)
        #expect(added[0].displayName == "test.txt")
        #expect(FileManager.default.fileExists(atPath: added[0].shelfURL.path))

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Add multiple files at once")
    func addMultipleFiles() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let file1 = try makeTestFile(in: sourceDir, name: "a.txt", content: "aaa")
        let file2 = try makeTestFile(in: sourceDir, name: "b.txt", content: "bbb")
        let file3 = try makeTestFile(in: sourceDir, name: "c.txt", content: "ccc")

        let added = manager.addFiles(from: [file1, file2, file3])
        #expect(added.count == 3)
        #expect(manager.items.count == 3)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Adding preserves original filename")
    func preservesFilename() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir, name: "my-document.pdf")

        let added = manager.addFiles(from: [fileURL])
        #expect(added.count == 1)
        #expect(added[0].displayName == "my-document.pdf")
        #expect(added[0].shelfURL.lastPathComponent == "my-document.pdf")

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Adding nonexistent file returns empty")
    func addNonexistentFile() throws {
        let (manager, shelfDir) = try makeManager()
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).txt")

        let added = manager.addFiles(from: [fakeURL])
        #expect(added.isEmpty)
        #expect(manager.items.isEmpty)

        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("totalBytes reflects added files")
    func totalBytesUpdates() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir, content: "hello world")

        manager.addFiles(from: [fileURL])
        #expect(manager.totalBytes > 0)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - Removing files

    @Test("Remove item by ID")
    func removeItem() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)

        let added = manager.addFiles(from: [fileURL])
        let itemID = added[0].id

        let removed = manager.removeItem(itemID)
        #expect(removed == true)
        #expect(manager.items.isEmpty)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Remove nonexistent ID returns false")
    func removeNonexistentItem() throws {
        let (manager, shelfDir) = try makeManager()
        let result = manager.removeItem(UUID())
        #expect(result == false)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Clear all removes everything")
    func clearAll() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let file1 = try makeTestFile(in: sourceDir, name: "a.txt")
        let file2 = try makeTestFile(in: sourceDir, name: "b.txt")

        manager.addFiles(from: [file1, file2])
        #expect(manager.items.count == 2)

        manager.clearAll()
        #expect(manager.items.isEmpty)
        #expect(manager.totalBytes == 0)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - Expiry

    @Test("removeExpiredItems removes old items")
    func removeExpiredItems() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        manager.expiryInterval = 0 // Expire immediately

        let fileURL = try makeTestFile(in: sourceDir)
        manager.addFiles(from: [fileURL])
        #expect(manager.items.count == 1)

        manager.removeExpiredItems()
        #expect(manager.items.isEmpty)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("removeExpiredItems keeps fresh items")
    func keepsNonExpiredItems() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        manager.expiryInterval = 3600 // 1 hour

        let fileURL = try makeTestFile(in: sourceDir)
        manager.addFiles(from: [fileURL])

        manager.removeExpiredItems()
        #expect(manager.items.count == 1)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - Capacity limits

    @Test("Max items enforces limit by removing oldest")
    func maxItemsEnforced() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        manager.maxItems = 2

        let file1 = try makeTestFile(in: sourceDir, name: "first.txt", content: "1")
        let file2 = try makeTestFile(in: sourceDir, name: "second.txt", content: "2")
        let file3 = try makeTestFile(in: sourceDir, name: "third.txt", content: "3")

        manager.addFiles(from: [file1])
        manager.addFiles(from: [file2])
        #expect(manager.items.count == 2)

        manager.addFiles(from: [file3])
        #expect(manager.items.count == 2)
        // Oldest (first.txt) should be gone
        #expect(manager.items.first?.displayName == "second.txt")
        #expect(manager.items.last?.displayName == "third.txt")

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Max bytes rejects oversized addition")
    func maxBytesEnforced() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        manager.maxTotalBytes = 5 // Only 5 bytes allowed

        let fileURL = try makeTestFile(in: sourceDir, content: "this is way more than 5 bytes")

        let added = manager.addFiles(from: [fileURL])
        #expect(added.isEmpty)
        #expect(manager.items.isEmpty)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - Shelf URL lookup

    @Test("shelfURL returns URL for valid item ID")
    func shelfURLLookup() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)

        let added = manager.addFiles(from: [fileURL])
        let url = manager.shelfURL(for: added[0].id)
        #expect(url != nil)
        #expect(url == added[0].shelfURL)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("shelfURL returns nil for unknown ID")
    func shelfURLUnknownID() throws {
        let (manager, shelfDir) = try makeManager()
        #expect(manager.shelfURL(for: UUID()) == nil)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - Callbacks

    @Test("onItemsChanged fires on add")
    func callbackOnAdd() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)

        nonisolated(unsafe) var callCount = 0
        manager.onItemsChanged = { callCount += 1 }

        manager.addFiles(from: [fileURL])
        #expect(callCount == 1)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("onItemsChanged fires on remove")
    func callbackOnRemove() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)

        let added = manager.addFiles(from: [fileURL])

        nonisolated(unsafe) var callCount = 0
        manager.onItemsChanged = { callCount += 1 }

        manager.removeItem(added[0].id)
        #expect(callCount == 1)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("onItemsChanged fires on clearAll")
    func callbackOnClearAll() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)
        manager.addFiles(from: [fileURL])

        nonisolated(unsafe) var callCount = 0
        manager.onItemsChanged = { callCount += 1 }

        manager.clearAll()
        #expect(callCount == 1)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - Cleanup

    @Test("cleanupAll removes shelf directory")
    func cleanupAll() throws {
        let shelfDir = try makeTempDirectory()
        let manager = FileShelfManager(directory: shelfDir)
        try manager.ensureShelfDirectory()

        manager.cleanupAll()
        #expect(!FileManager.default.fileExists(atPath: shelfDir.path))
    }

    // MARK: - Timer

    @Test("Start and stop expiry timer")
    func expiryTimerLifecycle() throws {
        let (manager, shelfDir) = try makeManager()
        manager.startExpiryTimer()
        // Starting again should not crash (replaces timer)
        manager.startExpiryTimer()
        manager.stopExpiryTimer()
        // Stopping again should not crash
        manager.stopExpiryTimer()
        try? FileManager.default.removeItem(at: shelfDir)
    }
}
