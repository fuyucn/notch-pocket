import AppKit

@MainActor
public final class NotchDropForwarder: NSView {
    public var onDropFiles: ((_ urls: [URL], _ sourceAppName: String?) -> Bool)?
    public var onDraggingChanged: ((_ isInside: Bool, _ fileNames: [String]) -> Void)?
    /// Called during drag with the cursor location in this view's coordinates.
    /// Owner can update `viewModel.isDragOverAirDrop` for visual highlight.
    public var onDragMoved: ((_ pointInView: NSPoint) -> Void)?
    /// Called on drop when the drop location falls inside the AirDrop
    /// region. Owner kicks off AirDrop with the URLs and returns true iff
    /// they were accepted (so the shelf can be bypassed).
    public var onDropOnAirDrop: ((_ urls: [URL]) -> Bool)?
    /// Return the AirDrop button's rect in the forwarder's coordinate space,
    /// or nil if it isn't currently shown.
    public var airDropRectProvider: (() -> NSRect?)?

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
        let point = convert(sender.draggingLocation, from: nil)
        onDragMoved?(point)
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        onDragMoved?(point)
        return .copy
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDraggingChanged?(false, [])
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = Self.readURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        // Drop on AirDrop region → bypass shelf, hand off to AirDrop.
        let point = convert(sender.draggingLocation, from: nil)
        if let rect = airDropRectProvider?(), rect.contains(point) {
            return onDropOnAirDrop?(urls) ?? false
        }

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
