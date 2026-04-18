# Shelf Storage Modes: Reference vs. Local Copy

**Branch:** continue on `plan-7-airdrop-drop-target` (or new `plan-8-storage-modes`; tbd)

**Goal:** Let shelf items be stored either as a **reference** (security-scoped bookmark of the original file, Dropover-style) or as a **local copy** (current behavior, NotchDrop-style). User picks via a new Settings picker. Default: Reference.

## Why

- **Reference mode** uses zero extra disk, avoids -8058 entirely (drag-out hands the real original URL to Finder, which is a user file — never a private Library path), and matches the most popular Mac shelf app (Dropover).
- **Local copy mode** is safer when the user drops temp / downloaded files they expect to delete soon; originals vanishing doesn't break the shelf.
- Both modes have legitimate use cases — ship both, user decides.

## User-facing changes

- **Settings → Shelf → "Storage mode"**, segmented: `Reference · Local copy`. Default `Reference`.
- Mode setting applies to **future** adds. Existing items retain whichever mode they were created under. Switching the mode doesn't migrate or drop existing items.
- **Missing file handling**: when the underlying file a reference-mode item points to is gone, `FileShelfManager` silently removes the stale entry on next access (no UI warning).
- `removeOnDragOut` remains. Semantics unified across modes:
  - `true` (default): drop successful → item removed from shelf (file on disk untouched in both modes).
  - `false`: item stays after drop.

## Implementation sketch

### `ShelfItem` — mode-aware

```swift
public enum ShelfItemStorage: Sendable, Codable, Equatable {
    /// Security-scoped bookmark of the original file on disk.
    case reference(Data)
    /// File lives under the shelf directory; URL is stable for the app's
    /// lifetime.
    case localCopy(URL)
}

public struct ShelfItem: Sendable, Identifiable {
    public let id: UUID
    public let storage: ShelfItemStorage
    public let displayName: String
    public let addedAt: Date
    public let fileSize: Int64
    public let sourceAppName: String?
    public let fileExtension: String?

    /// Resolve to a URL. For `.reference`, this resolves the bookmark (which
    /// may fail if the original file moved/was deleted — caller should
    /// treat `nil` as "file gone, drop the shelf item").
    public func resolvedURL() -> URL? { ... }
}
```

### `FileShelfManager.addFiles`

Signature gains an optional `storageOverride: ShelfItemStorage.Mode?` so callers (mostly `DropForwarder`) can force a mode; by default reads from settings.

```swift
public func addFiles(from urls: [URL], sourceAppName: String? = nil) -> [ShelfItem] {
    let mode = settings.storageMode  // reference | localCopy
    for url in urls {
        let storage: ShelfItemStorage = {
            switch mode {
            case .reference:
                if let data = try? url.bookmarkData(options: [.withSecurityScope], ...) {
                    return .reference(data)
                }
                fallthrough  // fall back to copy if bookmark creation fails
            case .localCopy:
                let itemDir = shelfDirectory.appendingPathComponent(UUID().uuidString)
                try? FileManager.default.createDirectory(at: itemDir, ...)
                let dest = itemDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
                return .localCopy(dest)
            }
        }()
        items.append(ShelfItem(storage: storage, ...))
    }
}
```

### `resolvedURL()` failure → silent cleanup

`FileShelfManager` exposes a `validateItems()` helper that walks the list, calls `resolvedURL()` on each, drops entries whose URL is nil (bookmark resolve failed or file doesn't exist). Called:
- On app launch
- When the shelf becomes visible (status changes to `.opened`)
- Just before a drag-out begins

### Drag source path

`FileDragSourceView` and `AllDragHandle` currently use `NSFilePromiseProvider` which writes a copy. In **reference mode**, skip the promise machinery entirely and hand the **real URL directly**:

```swift
let dragItem: NSDraggingItem
switch item.storage {
case .reference(let data):
    // Re-resolve bookmark at drag-start. If it fails, do nothing.
    guard let url = resolve(data) else { return }
    dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
case .localCopy(let url):
    // Continue using NSFilePromiseProvider so Finder never touches our
    // Application Support file directly (avoids -8058).
    let provider = NSFilePromiseProvider(...)
    dragItem = NSDraggingItem(pasteboardWriter: provider)
}
```

Shelf-side "remove on drag out" still hooks in: reference mode fires on `endedAt:operation:` (NSURL drags behave normally with that callback), local-copy mode continues using `writePromiseTo` as the success signal.

### SettingsManager

Add `storageMode: ShelfStorageMode` enum (`reference` = 0, `localCopy` = 1). Default `.reference`. Register in `registerDefaults`.

### SettingsView

Add a Picker in the Shelf section above `removeOnDragOut`.

### Persistence

Currently `FileShelfManager.items` is in-memory only (shelf is wiped on relaunch). **Phase 1 ships without disk persistence** — the stored `bookmarkData` does not need to survive relaunch if the shelf itself doesn't. Phase 2 (separate plan) can serialize `[ShelfItem]` to disk.

## Edge cases / risks

| Case | Handling |
|---|---|
| Bookmark resolution requires security-scoped access call (`startAccessingSecurityScopedResource`) | Wrap resolve with start/stop; release once drag or preview finishes. |
| Sandboxing — app isn't sandboxed today, so security-scoped bookmarks are overkill but still work. Plain `url.bookmarkData()` is sufficient. | Use non-security-scoped bookmarks for simplicity. Revisit if app goes sandboxed. |
| Original file is on an unmounted external volume | `resolvedURL()` returns nil → silent drop. |
| User switches modes while shelf has 20 items | Existing items stay in their original mode; switch only affects future adds. Tag each item's `storage` accordingly. |
| Bookmark creation itself fails (rare — permissions) | Fall through to `localCopy` with a logged note. |

## Testing

- Unit tests for `ShelfItem.resolvedURL` (hit / miss)
- Unit tests for `FileShelfManager` with both modes, assert storage variant is honored
- Unit tests for missing-file cleanup via `validateItems()`
- Manual: drag-out in each mode, verify Finder operation, shelf behavior for both `removeOnDragOut` toggles

## Out of scope (future phases)

- Persisting shelf across app relaunches
- Showing "missing" indicator UI instead of silent removal
- Auto-migrating between modes
