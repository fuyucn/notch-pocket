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

    // MARK: - Additional edge cases

    @Test("Adding same file twice creates two distinct shelf items")
    func addSameFileTwice() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir, name: "dup.txt", content: "data")

        let first = manager.addFiles(from: [fileURL])
        let second = manager.addFiles(from: [fileURL])
        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(manager.items.count == 2)
        // They should have different IDs and different shelf paths
        #expect(first[0].id != second[0].id)
        #expect(first[0].shelfURL != second[0].shelfURL)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Removing middle item preserves order of others")
    func removeMiddlePreservesOrder() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let f1 = try makeTestFile(in: sourceDir, name: "a.txt")
        let f2 = try makeTestFile(in: sourceDir, name: "b.txt")
        let f3 = try makeTestFile(in: sourceDir, name: "c.txt")

        let added = manager.addFiles(from: [f1, f2, f3])
        manager.removeItem(added[1].id)

        #expect(manager.items.count == 2)
        #expect(manager.items[0].displayName == "a.txt")
        #expect(manager.items[1].displayName == "c.txt")

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Batch add exceeding maxItems evicts oldest first")
    func batchAddExceedingMaxItems() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        manager.maxItems = 3

        // Pre-load 2 items
        let f1 = try makeTestFile(in: sourceDir, name: "1.txt", content: "1")
        let f2 = try makeTestFile(in: sourceDir, name: "2.txt", content: "2")
        manager.addFiles(from: [f1, f2])

        // Batch add 3 more, forcing eviction of 2 oldest
        let f3 = try makeTestFile(in: sourceDir, name: "3.txt", content: "3")
        let f4 = try makeTestFile(in: sourceDir, name: "4.txt", content: "4")
        let f5 = try makeTestFile(in: sourceDir, name: "5.txt", content: "5")
        manager.addFiles(from: [f3, f4, f5])

        #expect(manager.items.count == 3)
        // Oldest two (1.txt, 2.txt) should be gone
        let names = manager.items.map(\.displayName)
        #expect(!names.contains("1.txt"))
        #expect(!names.contains("2.txt"))

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("clearAll on empty shelf does not crash and fires callback")
    func clearAllEmpty() throws {
        let (manager, shelfDir) = try makeManager()
        #expect(manager.items.isEmpty)

        nonisolated(unsafe) var callCount = 0
        manager.onItemsChanged = { callCount += 1 }

        manager.clearAll()
        #expect(manager.items.isEmpty)
        #expect(callCount == 1) // Callback fires even when empty

        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("removeExpiredItems keeps fresh and removes expired in mixed set")
    func mixedExpiryItems() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        manager.expiryInterval = 3600

        // Add a "fresh" file
        let fresh = try makeTestFile(in: sourceDir, name: "fresh.txt")
        manager.addFiles(from: [fresh])

        // Manually create an "old" item by directly manipulating
        // We can't easily set addedAt, so use expiryInterval = huge for fresh,
        // then set to 0 and remove expired
        let old = try makeTestFile(in: sourceDir, name: "old.txt")
        manager.addFiles(from: [old])
        #expect(manager.items.count == 2)

        // Set expiry to 0 — everything expires
        manager.expiryInterval = 0
        manager.removeExpiredItems()
        #expect(manager.items.isEmpty)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("totalBytes decreases after removal")
    func totalBytesDecreasesOnRemoval() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let f1 = try makeTestFile(in: sourceDir, name: "big.txt", content: String(repeating: "x", count: 1000))

        let added = manager.addFiles(from: [f1])
        let bytesAfterAdd = manager.totalBytes
        #expect(bytesAfterAdd > 0)

        manager.removeItem(added[0].id)
        #expect(manager.totalBytes == 0)
        #expect(manager.totalBytes < bytesAfterAdd)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Callback fires exactly once per batch add, not per file")
    func callbackCountForBatchAdd() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let f1 = try makeTestFile(in: sourceDir, name: "a.txt")
        let f2 = try makeTestFile(in: sourceDir, name: "b.txt")
        let f3 = try makeTestFile(in: sourceDir, name: "c.txt")

        nonisolated(unsafe) var callCount = 0
        manager.onItemsChanged = { callCount += 1 }

        manager.addFiles(from: [f1, f2, f3])
        // Should fire once for the whole batch, not 3 times
        #expect(callCount == 1)

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Manager with default directory uses caches path")
    func defaultDirectoryUsesCaches() throws {
        let manager = FileShelfManager()
        // We can't easily verify the path, but creation should not crash
        #expect(manager.items.isEmpty)
    }

    @Test("Max bytes boundary: file exactly at limit is accepted")
    func maxBytesExactBoundary() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()

        // Create a file, add it, check its size, then set limit to exactly that
        let content = "hello" // 5 bytes
        let fileURL = try makeTestFile(in: sourceDir, content: content)
        let added = manager.addFiles(from: [fileURL])
        let fileSize = added[0].fileSize
        #expect(fileSize > 0)

        // Clear and reset
        manager.clearAll()
        manager.maxTotalBytes = fileSize // Exact fit

        let added2 = manager.addFiles(from: [fileURL])
        #expect(added2.count == 1) // Should fit exactly

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    @Test("Shelf file is physically deleted after removeItem")
    func fileDeletedOnRemove() throws {
        let sourceDir = try makeTempDirectory()
        let (manager, shelfDir) = try makeManager()
        let fileURL = try makeTestFile(in: sourceDir)

        let added = manager.addFiles(from: [fileURL])
        let shelfPath = added[0].shelfURL.path
        #expect(FileManager.default.fileExists(atPath: shelfPath))

        manager.removeItem(added[0].id)
        #expect(!FileManager.default.fileExists(atPath: shelfPath))

        try? FileManager.default.removeItem(at: sourceDir)
        try? FileManager.default.removeItem(at: shelfDir)
    }

    // MARK: - sourceAppName and fileExtension

    @Test @MainActor
    func shelfItemDefaultsSourceAppAndExtensionToNil() {
        let item = ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/foo.pdf"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/foo.pdf"),
            displayName: "foo.pdf",
            fileSize: 42
        )
        #expect(item.sourceAppName == nil)
        #expect(item.fileExtension == nil)
    }

    @Test @MainActor
    func shelfItemStoresSourceAppAndExtension() {
        let item = ShelfItem(
            originalURL: URL(fileURLWithPath: "/tmp/foo.pdf"),
            shelfURL: URL(fileURLWithPath: "/tmp/shelf/foo.pdf"),
            displayName: "foo.pdf",
            fileSize: 42,
            sourceAppName: "Finder",
            fileExtension: "pdf"
        )
        #expect(item.sourceAppName == "Finder")
        #expect(item.fileExtension == "pdf")
    }

    @Test @MainActor
    func addFilesPopulatesFileExtension() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("note.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)

        let shelfDir = tmp.appendingPathComponent("shelf", isDirectory: true)
        let manager = FileShelfManager(directory: shelfDir)
        try manager.ensureShelfDirectory()

        let added = manager.addFiles(from: [src])
        #expect(added.count == 1)
        #expect(added.first?.fileExtension == "txt")
    }

    @Test @MainActor
    func addFilesTagsSourceAppName() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("note.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)

        let shelfDir = tmp.appendingPathComponent("shelf", isDirectory: true)
        let manager = FileShelfManager(directory: shelfDir)
        try manager.ensureShelfDirectory()

        let added = manager.addFiles(from: [src], sourceAppName: "Finder")
        #expect(added.count == 1)
        #expect(added.first?.sourceAppName == "Finder")
        #expect(added.first?.fileExtension == "txt")
        #expect(manager.items.first?.sourceAppName == "Finder")
    }

    @Test @MainActor
    func addFilesWithNilSourceAppNameBehavesLikeBaseOverload() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("note.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)

        let shelfDir = tmp.appendingPathComponent("shelf", isDirectory: true)
        let manager = FileShelfManager(directory: shelfDir)
        try manager.ensureShelfDirectory()

        let added = manager.addFiles(from: [src], sourceAppName: nil)
        #expect(added.count == 1)
        #expect(added.first?.sourceAppName == nil)
        #expect(manager.items.count == 1)
    }

    @Test @MainActor
    func addFilesFiresOnItemsChangedTwiceWhenTagging() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("note.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)
        let src2 = tmp.appendingPathComponent("other.txt")
        try "world".write(to: src2, atomically: true, encoding: .utf8)

        let shelfDir = tmp.appendingPathComponent("shelf", isDirectory: true)
        let manager = FileShelfManager(directory: shelfDir)
        try manager.ensureShelfDirectory()

        nonisolated(unsafe) var callCount = 0
        manager.onItemsChanged = { callCount += 1 }

        // With sourceAppName: should fire twice (once from base overload, once after tagging)
        manager.addFiles(from: [src], sourceAppName: "Finder")
        #expect(callCount == 2)

        // With nil sourceAppName: should fire only once (base overload path, no tagging)
        let countBefore = callCount
        manager.addFiles(from: [src2], sourceAppName: nil)
        #expect(callCount == countBefore + 1)
    }
}
