import AppKit
import UniformTypeIdentifiers

/// An NSView that acts as the drag destination for the DropZone panel.
/// Handles NSDraggingDestination protocol, visual feedback during hover,
/// and coordinates with FileShelfManager for file storage.
@MainActor
public final class DragDestinationView: NSView {
    // MARK: - Dependencies

    public var fileShelfManager: FileShelfManager?

    // MARK: - Callbacks

    /// Called when a drag session enters the view (for panel expand).
    public var onDragEntered: (@MainActor () -> Void)?
    /// Called when a drag session exits the view without a drop.
    public var onDragExited: (@MainActor () -> Void)?
    /// Called after files are successfully dropped with the count of new items.
    public var onFilesDropped: (@MainActor (Int) -> Void)?

    // MARK: - Visual state

    /// Whether a drag is currently hovering over this view.
    public private(set) var isHighlighted: Bool = false

    /// Number of items in the current drag session.
    public private(set) var dragItemCount: Int = 0

    // MARK: - Highlight layer

    private var highlightLayer: CAShapeLayer?

    /// Accepted pasteboard types for file drops.
    private static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .filePromise,
    ]

    /// Apple's private pasteboard type that carries the source app's bundle identifier
    /// during drag-and-drop. Present for most AppKit-based drag sources (Finder, Safari, Preview…).
    public static let sourceAppBundleIDType =
        NSPasteboard.PasteboardType("com.apple.pasteboard.source-app-bundle-identifier")

    /// Resolve a bundle identifier to the app's display name via NSWorkspace + Bundle.
    /// Returns nil if the bundle ID is unknown or the Info.plist has no `CFBundleName`.
    public static func sourceAppName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
    }

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupView() {
        wantsLayer = true
        registerForDraggedTypes(Self.acceptedTypes)
    }

    // MARK: - NSDraggingDestination

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty else { return [] }

        dragItemCount = urls.count
        setHighlighted(true)
        onDragEntered?()
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty else { return [] }

        dragItemCount = urls.count
        return .copy
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setHighlighted(false)
        dragItemCount = 0
        onDragExited?()
    }

    public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender)
        return !urls.isEmpty
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty, let manager = fileShelfManager else { return false }

        let bundleID = sender.draggingPasteboard.string(forType: Self.sourceAppBundleIDType)
        let appName = bundleID.flatMap(Self.sourceAppName(forBundleID:))
        let added = manager.addFiles(from: urls, sourceAppName: appName)

        setHighlighted(false)
        dragItemCount = 0

        if !added.isEmpty {
            onFilesDropped?(added.count)
            return true
        }
        return false
    }

    public override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        setHighlighted(false)
        dragItemCount = 0
    }

    // MARK: - Visual feedback

    private func setHighlighted(_ highlighted: Bool) {
        guard isHighlighted != highlighted else { return }
        isHighlighted = highlighted

        if highlighted {
            showHighlight()
        } else {
            hideHighlight()
        }
    }

    private func showHighlight() {
        guard let layer else { return }

        if highlightLayer == nil {
            let shape = CAShapeLayer()
            shape.fillColor = nil
            shape.lineWidth = 2
            shape.lineDashPattern = [6, 4]
            shape.cornerRadius = NotchGeometry.cornerRadius
            layer.addSublayer(shape)
            highlightLayer = shape
        }

        guard let hl = highlightLayer else { return }
        let inset = bounds.insetBy(dx: 3, dy: 3)
        hl.path = CGPath(roundedRect: inset, cornerWidth: NotchGeometry.cornerRadius - 3, cornerHeight: NotchGeometry.cornerRadius - 3, transform: nil)
        hl.frame = bounds
        hl.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor

        // Animate the dash phase for a marching ants effect
        let dashAnim = CABasicAnimation(keyPath: "lineDashPhase")
        dashAnim.fromValue = 0
        dashAnim.toValue = 20
        dashAnim.duration = 0.8
        dashAnim.repeatCount = .infinity
        hl.add(dashAnim, forKey: "dashPhase")
    }

    private func hideHighlight() {
        highlightLayer?.removeAllAnimations()
        highlightLayer?.removeFromSuperlayer()
        highlightLayer = nil
    }

    // MARK: - Pasteboard extraction

    /// Extract file URLs from a drag info's pasteboard.
    /// Handles both direct file URLs and file promises.
    private func extractFileURLs(from info: any NSDraggingInfo) -> [URL] {
        let pasteboard = info.draggingPasteboard

        // Try direct file URLs first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return urls
        }

        // Try file promise receiver
        if let filePromises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !filePromises.isEmpty {
            // File promises require async resolution — for now, extract what we can
            // from the pasteboard items as file URLs
            var urls: [URL] = []
            for item in pasteboard.pasteboardItems ?? [] {
                if let urlString = item.string(forType: .fileURL),
                   let url = URL(string: urlString) {
                    urls.append(url)
                }
            }
            return urls
        }

        return []
    }

    // MARK: - Hit testing

    /// Allow non-drag mouse events (clicks) to pass through to views below.
    /// This view only needs to intercept drag-and-drop operations.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        // Update highlight frame if visible
        if isHighlighted, let hl = highlightLayer {
            let inset = bounds.insetBy(dx: 3, dy: 3)
            hl.path = CGPath(roundedRect: inset, cornerWidth: NotchGeometry.cornerRadius - 3, cornerHeight: NotchGeometry.cornerRadius - 3, transform: nil)
            hl.frame = bounds
        }
    }
}

// MARK: - NSPasteboard.PasteboardType extension

extension NSPasteboard.PasteboardType {
    /// The file promise pasteboard type.
    static let filePromise = NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData")
}
