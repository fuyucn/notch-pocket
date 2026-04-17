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
        let names = Self.readFileNames(from: sender.draggingPasteboard)
        onDraggingChanged?(true, names)
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDraggingChanged?(false, [])
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
