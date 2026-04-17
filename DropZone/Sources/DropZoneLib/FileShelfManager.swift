import AppKit
import UniformTypeIdentifiers

/// Represents a single file stored in the temporary shelf.
public struct ShelfItem: Sendable, Identifiable {
    public let id: UUID
    /// Original file URL (where the file came from).
    public let originalURL: URL
    /// URL in the temporary shelf cache directory.
    public let shelfURL: URL
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
        originalURL: URL,
        shelfURL: URL,
        displayName: String,
        addedAt: Date = Date(),
        fileSize: Int64,
        sourceAppName: String? = nil,
        fileExtension: String? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.shelfURL = shelfURL
        self.displayName = displayName
        self.addedAt = addedAt
        self.fileSize = fileSize
        self.sourceAppName = sourceAppName
        self.fileExtension = fileExtension
    }
}

/// Manages temporary file storage for the DropZone shelf.
///
/// Files dropped onto the shelf are hard-linked (same volume) or copied (cross-volume)
/// into a cache directory. Each file gets a UUID subdirectory to avoid name collisions
/// while preserving the original filename.
@MainActor
public final class FileShelfManager {
    // MARK: - Configuration

    /// How long files remain on the shelf before auto-expiry.
    public var expiryInterval: TimeInterval = 3600 // 1 hour default

    /// Maximum total shelf storage in bytes (default 2GB).
    public var maxTotalBytes: Int64 = 2_147_483_648

    /// Maximum number of items on the shelf.
    public var maxItems: Int = 50

    // MARK: - State

    /// Current items on the shelf, ordered by addition time.
    public private(set) var items: [ShelfItem] = []

    /// Total bytes currently used by shelf items.
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
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.shelfDirectory = directory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.shelfDirectory = appSupport.appendingPathComponent("NotchPocket/shelf", isDirectory: true)
        }
    }

    // MARK: - Public API

    /// Add files from the given URLs to the shelf.
    /// Returns the newly created ShelfItems, or an empty array if all failed.
    @discardableResult
    public func addFiles(from urls: [URL]) -> [ShelfItem] {
        var added: [ShelfItem] = []

        for url in urls {
            // Enforce max items — remove oldest if needed
            if items.count >= maxItems, let oldest = items.first {
                removeItem(oldest.id)
            }

            guard let item = storeFile(from: url) else { continue }

            // Enforce max total bytes
            if totalBytes + item.fileSize > maxTotalBytes {
                // Clean up the file we just stored since it won't fit
                try? fileManager.removeItem(at: item.shelfURL.deletingLastPathComponent())
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
                originalURL: existing.originalURL,
                shelfURL: existing.shelfURL,
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
        // Remove the UUID subdirectory and its contents
        try? fileManager.removeItem(at: item.shelfURL.deletingLastPathComponent())
        items.remove(at: index)
        onItemsChanged?()
        return true
    }

    /// Remove all items from the shelf.
    public func clearAll() {
        for item in items {
            try? fileManager.removeItem(at: item.shelfURL.deletingLastPathComponent())
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

    /// Get the shelf URL for an item by ID (for providing to drag operations).
    public func shelfURL(for id: UUID) -> URL? {
        items.first(where: { $0.id == id })?.shelfURL
    }

    // MARK: - Private

    private func storeFile(from sourceURL: URL) -> ShelfItem? {
        let itemID = UUID()
        let itemDir = shelfDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let fileName = sourceURL.lastPathComponent
        let destURL = itemDir.appendingPathComponent(fileName)

        // Try hard-link first (same volume, no extra disk usage), fall back to copy
        do {
            try fileManager.linkItem(at: sourceURL, to: destURL)
        } catch {
            do {
                try fileManager.copyItem(at: sourceURL, to: destURL)
            } catch {
                try? fileManager.removeItem(at: itemDir)
                return nil
            }
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
            originalURL: sourceURL,
            shelfURL: destURL,
            displayName: fileName,
            fileSize: fileSize,
            sourceAppName: nil,
            fileExtension: ext.isEmpty ? nil : ext
        )
    }
}
