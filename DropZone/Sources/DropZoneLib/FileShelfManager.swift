import AppKit
import UniformTypeIdentifiers

// MARK: - ShelfItemStorage

/// How a shelf item's file is stored.
public enum ShelfItemStorage: Sendable, Codable, Equatable {
    /// A bookmark pointing at the original file. Zero extra disk space.
    case reference(Data)
    /// File was copied into the shelf directory. Lives under `shelfURL`.
    case localCopy(URL)

    /// True when this is a reference (bookmark) item.
    public var isReference: Bool {
        if case .reference = self { return true }
        return false
    }
}

// MARK: - ShelfItem

/// Represents a single file stored in the temporary shelf.
public struct ShelfItem: Sendable, Identifiable {
    public let id: UUID
    /// How the file is stored (bookmark reference or local copy).
    public let storage: ShelfItemStorage
    /// The canonical source URL used for duplicate detection. Stored at add
    /// time so it remains stable regardless of storage mode.
    public let sourceURL: URL
    /// Display name (original filename).
    public let displayName: String
    /// When the file was added to the shelf.
    public let addedAt: Date
    /// File size in bytes.
    public let fileSize: Int64
    /// Name of the application the file was dragged from, if known.
    public let sourceAppName: String?
    /// Lowercased file extension (without the dot), if any.
    public let fileExtension: String?

    public init(
        id: UUID = UUID(),
        storage: ShelfItemStorage,
        sourceURL: URL,
        displayName: String,
        addedAt: Date = Date(),
        fileSize: Int64,
        sourceAppName: String? = nil,
        fileExtension: String? = nil
    ) {
        self.id = id
        self.storage = storage
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.addedAt = addedAt
        self.fileSize = fileSize
        self.sourceAppName = sourceAppName
        self.fileExtension = fileExtension
    }

    /// Resolve to a concrete URL.
    ///
    /// - For `.localCopy`: returns the shelf URL, or `nil` if the file no
    ///   longer exists on disk (e.g. someone deleted the shelf dir).
    /// - For `.reference`: resolves the bookmark. Returns `nil` if the
    ///   bookmark is stale or the file has been moved/deleted.
    public func resolvedURL() -> URL? {
        switch storage {
        case .localCopy(let url):
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .reference(let data):
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { return nil }
            if stale { return nil }
            return url
        }
    }
}

// MARK: - FileShelfManager

/// Manages temporary file storage for the DropZone shelf.
///
/// Files dropped onto the shelf are either bookmarked (reference mode) or
/// copied (local-copy mode) into a cache directory. Each local-copy item gets
/// a UUID subdirectory to avoid name collisions while preserving the original
/// filename.
@MainActor
public final class FileShelfManager {
    // MARK: - Configuration

    /// How long files remain on the shelf before auto-expiry.
    public var expiryInterval: TimeInterval = 3600 // 1 hour default

    /// Maximum total shelf storage in bytes (default 2GB).
    public var maxTotalBytes: Int64 = 2_147_483_648

    /// Maximum number of items on the shelf.
    public var maxItems: Int = 50

    /// Provider for the current storage mode. Injected at init time so the
    /// manager itself remains agnostic to UserDefaults / SettingsManager.
    public var storageModeProvider: () -> ShelfStorageMode

    // MARK: - State

    /// Current items on the shelf, ordered by addition time.
    public private(set) var items: [ShelfItem] = []

    /// Total bytes currently used by shelf items (local-copy only; reference
    /// items count 0 because the file lives elsewhere).
    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Storage

    private let shelfDirectory: URL
    private let fileManager: FileManager
    private var expiryTimer: Timer?

    /// Callback fired when items change (add/remove).
    public var onItemsChanged: (@MainActor @Sendable () -> Void)?

    // MARK: - Init

    /// Create a FileShelfManager with a specific storage directory.
    /// - Parameter directory: The root directory for shelf storage. If nil,
    ///   uses `~/Library/Application Support/NotchPocket/shelf`. We
    ///   deliberately avoid `~/Library/Caches` so the OS can perform
    ///   `NSDragOperation.move` on shelved files without refusing with
    ///   `NSFileWriteUnknownError` (-8058).
    /// - Parameter storageModeProvider: Closure that returns the current
    ///   storage mode at the time a file is added. Defaults to `.reference`.
    public init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        storageModeProvider: @escaping () -> ShelfStorageMode = { .reference }
    ) {
        self.fileManager = fileManager
        self.storageModeProvider = storageModeProvider
        if let directory {
            self.shelfDirectory = directory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.shelfDirectory = appSupport.appendingPathComponent("NotchPocket/shelf", isDirectory: true)
        }
    }

    // MARK: - Public API

    /// Remove shelf items whose underlying file can no longer be resolved.
    ///
    /// Called on app launch and when the shelf becomes visible. If any items
    /// were dropped, `onItemsChanged` fires once.
    public func validateItems() {
        let before = items.count
        items = items.filter { $0.resolvedURL() != nil }
        if items.count != before {
            onItemsChanged?()
        }
    }

    /// Add files from the given URLs to the shelf.
    /// Returns the newly created ShelfItems, or an empty array if all failed.
    @discardableResult
    public func addFiles(from urls: [URL]) -> [ShelfItem] {
        validateItems()
        let mode = storageModeProvider()
        var added: [ShelfItem] = []

        for url in urls {
            // Skip duplicates — an identical source path is already on the
            // shelf. Resolve symlinks first so /private/var and /var etc.
            // collapse to a single canonical path before comparing.
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            let alreadyShelved = items.contains { existing in
                existing.sourceURL.resolvingSymlinksInPath().standardizedFileURL == canonical
            }
            if alreadyShelved { continue }

            // Enforce max items — remove oldest if needed
            if items.count >= maxItems, let oldest = items.first {
                removeItem(oldest.id)
            }

            guard let item = makeItem(from: url, mode: mode) else { continue }

            // Enforce max total bytes (only meaningful for local-copy mode)
            if totalBytes + item.fileSize > maxTotalBytes {
                // Clean up any file we just stored since it won't fit
                if case .localCopy(let localURL) = item.storage {
                    try? fileManager.removeItem(at: localURL.deletingLastPathComponent())
                }
                continue
            }

            items.append(item)
            added.append(item)
        }

        if !added.isEmpty {
            onItemsChanged?()
        }
        return added
    }

    /// Add files and tag them with a source application name.
    /// Used when the drop pasteboard carries `com.apple.pasteboard.source-app-bundle-identifier`.
    @discardableResult
    public func addFiles(from urls: [URL], sourceAppName: String?) -> [ShelfItem] {
        let added = addFiles(from: urls)
        guard let sourceAppName, !added.isEmpty else { return added }
        let taggedIDs = Set(added.map { $0.id })
        items = items.map { existing in
            guard taggedIDs.contains(existing.id) else { return existing }
            return ShelfItem(
                id: existing.id,
                storage: existing.storage,
                sourceURL: existing.sourceURL,
                displayName: existing.displayName,
                addedAt: existing.addedAt,
                fileSize: existing.fileSize,
                sourceAppName: sourceAppName,
                fileExtension: existing.fileExtension
            )
        }
        onItemsChanged?()
        // Return the updated items (post-tag) so the caller sees the app name.
        return items.filter { taggedIDs.contains($0.id) }
    }

    /// Remove a specific item from the shelf.
    @discardableResult
    public func removeItem(_ id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let item = items[index]
        // For local-copy items, remove the UUID subdirectory and its contents
        if case .localCopy(let localURL) = item.storage {
            try? fileManager.removeItem(at: localURL.deletingLastPathComponent())
        }
        items.remove(at: index)
        onItemsChanged?()
        return true
    }

    /// Remove all items from the shelf.
    public func clearAll() {
        for item in items {
            if case .localCopy(let localURL) = item.storage {
                try? fileManager.removeItem(at: localURL.deletingLastPathComponent())
            }
        }
        items.removeAll()
        onItemsChanged?()
    }

    /// Remove expired items based on `expiryInterval`.
    public func removeExpiredItems() {
        let now = Date()
        let expired = items.filter { now.timeIntervalSince($0.addedAt) >= expiryInterval }
        for item in expired {
            removeItem(item.id)
        }
    }

    /// Start the expiry timer that periodically cleans up old items.
    public func startExpiryTimer() {
        stopExpiryTimer()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeExpiredItems()
            }
        }
    }

    /// Stop the expiry timer.
    public func stopExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    /// Clean up the entire shelf directory. Call on app termination.
    public func cleanupAll() {
        stopExpiryTimer()
        items.removeAll()
        try? fileManager.removeItem(at: shelfDirectory)
    }

    /// Ensure the shelf directory exists.
    public func ensureShelfDirectory() throws {
        try fileManager.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
    }

    // MARK: - File URLs for drag-out

    /// Get the resolved URL for an item by ID (for providing to drag operations).
    public func shelfURL(for id: UUID) -> URL? {
        items.first(where: { $0.id == id })?.resolvedURL()
    }

    // MARK: - Private

    private func makeItem(from sourceURL: URL, mode: ShelfStorageMode) -> ShelfItem? {
        let fileName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()

        switch mode {
        case .reference:
            // Build a non-security-scoped bookmark (app is not sandboxed).
            if let data = try? sourceURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                // Use 0 for fileSize — the file lives on the user's disk, not
                // our shelf directory, so we don't count it against the quota.
                return ShelfItem(
                    storage: .reference(data),
                    sourceURL: sourceURL,
                    displayName: fileName,
                    fileSize: 0,
                    fileExtension: ext.isEmpty ? nil : ext
                )
            }
            // Fallthrough: bookmark creation failed — store a local copy instead.
            fallthrough

        case .localCopy:
            return storeLocalCopy(from: sourceURL)
        }
    }

    private func storeLocalCopy(from sourceURL: URL) -> ShelfItem? {
        let itemID = UUID()
        let itemDir = shelfDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let fileName = sourceURL.lastPathComponent
        let destURL = itemDir.appendingPathComponent(fileName)

        // Always copy (not hard-link). Hard-links share an inode with the
        // source, which causes Finder to produce NSFileWriteUnknownError
        // (-8058) when the user later drags the shelf copy out (the OS
        // tries to rename/unlink an inode it can't reason about across
        // volumes). A plain copy makes the shelf item a truly independent
        // file that Finder can freely move.
        do {
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            try? fileManager.removeItem(at: itemDir)
            return nil
        }

        // Get file size
        let fileSize: Int64
        if let attrs = try? fileManager.attributesOfItem(atPath: destURL.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        let ext = sourceURL.pathExtension.lowercased()
        return ShelfItem(
            id: itemID,
            storage: .localCopy(destURL),
            sourceURL: sourceURL,
            displayName: fileName,
            fileSize: fileSize,
            fileExtension: ext.isEmpty ? nil : ext
        )
    }
}
