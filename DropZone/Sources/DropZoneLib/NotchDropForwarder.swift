import AppKit

@MainActor
public final class NotchDropForwarder: NSView {
    public var onDropFiles: ((_ urls: [URL], _ sourceAppName: String?) -> Bool)?
    public var onDraggingChanged: ((_ isInside: Bool, _ fileNames: [String]) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.pasteboardHasFileURLs(sender.draggingPasteboard) else {
            return []
        }
        let names = Self.readFileNames(from: sender.draggingPasteboard)
        onDraggingChanged?(true, names)
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.pasteboardHasFileURLs(sender.draggingPasteboard) ? .copy : []
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDraggingChanged?(false, [])
    }

    /// Check pasteboard for at least one URL that points to a real file on
    /// disk. Apps like Chrome publish `NSPasteboard.PasteboardType.fileURL`
    /// for window-drag / tab-drag content (download URLs, bookmark URLs) —
    /// the URL is a real `isFileURL == true` URL but the path doesn't
    /// actually exist on the filesystem. We insist on an existing file so
    /// that only real Finder-style file drags activate.
    static func pasteboardHasFileURLs(_ pb: NSPasteboard) -> Bool {
        let urls = readURLs(from: pb)
        let fm = FileManager.default
        return urls.contains { url in
            url.isFileURL && fm.fileExists(atPath: url.path)
        }
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = Self.readURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let bundleID = sender.draggingPasteboard.string(
            forType: NSPasteboard.PasteboardType("com.apple.pasteboard.source-app-bundle-identifier")
        )
        let app = bundleID.flatMap(Self.sourceAppName(forBundleID:))
        return onDropFiles?(urls, app) ?? false
    }

    static func readURLs(from pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func readFileNames(from pb: NSPasteboard) -> [String] {
        readURLs(from: pb).map { $0.lastPathComponent }
    }

    static func sourceAppName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
    }
}
