import AppKit
import QuickLookThumbnailing

/// Displays a single shelf item: thumbnail/icon, filename, and a remove button.
/// Supports being used as an NSDraggingSource to drag the file back out.
@MainActor
public final class FileThumbnailView: NSView, NSDraggingSource {
    // MARK: - Configuration

    /// The shelf item this view represents.
    public let item: ShelfItem

    /// Called when the user clicks the remove button.
    public var onRemove: (@MainActor (UUID) -> Void)?

    // MARK: - Visual constants

    private static let thumbnailSize = CGSize(width: 48, height: 48)
    private static let viewWidth: CGFloat = 64
    private static let viewHeight: CGFloat = 72
    private static let iconCornerRadius: CGFloat = 8
    private static let removeButtonSize: CGFloat = 16

    public static var itemSize: NSSize {
        NSSize(width: viewWidth, height: viewHeight)
    }

    // MARK: - Subviews

    private let imageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = iconCornerRadius
        iv.layer?.cornerCurve = .continuous
        iv.layer?.masksToBounds = true
        return iv
    }()

    private let nameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.85)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        return label
    }()

    private let removeButton: NSButton = {
        let button = NSButton()
        button.bezelStyle = .circular
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = removeButtonSize / 2
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        button.image = image?.withSymbolConfiguration(config)
        button.contentTintColor = .white.withAlphaComponent(0.9)
        button.isHidden = true // shown on hover
        return button
    }()

    // MARK: - State

    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private var dragStartPoint: NSPoint?

    // MARK: - Init

    public init(item: ShelfItem) {
        self.item = item
        super.init(frame: NSRect(origin: .zero, size: Self.itemSize))
        setupSubviews()
        loadThumbnail()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupSubviews() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        let thumbSize = Self.thumbnailSize
        let padding: CGFloat = (Self.viewWidth - thumbSize.width) / 2

        imageView.frame = NSRect(
            x: padding,
            y: Self.viewHeight - thumbSize.height - 4,
            width: thumbSize.width,
            height: thumbSize.height
        )
        addSubview(imageView)

        nameLabel.frame = NSRect(
            x: 2,
            y: 0,
            width: Self.viewWidth - 4,
            height: 14
        )
        addSubview(nameLabel)
        nameLabel.stringValue = item.displayName

        let btnSize = Self.removeButtonSize
        removeButton.frame = NSRect(
            x: Self.viewWidth - btnSize - 2,
            y: Self.viewHeight - btnSize - 2,
            width: btnSize,
            height: btnSize
        )
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        addSubview(removeButton)
    }

    private func loadThumbnail() {
        // Start with workspace icon
        let icon = NSWorkspace.shared.icon(forFile: item.shelfURL.path)
        icon.size = Self.thumbnailSize
        imageView.image = icon

        // Try QuickLook thumbnail for richer preview
        let request = QLThumbnailGenerator.Request(
            fileAt: item.shelfURL,
            size: Self.thumbnailSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let nsImage = representation?.nsImage else { return }
            DispatchQueue.main.async {
                self?.imageView.image = nsImage
            }
        }
    }

    // MARK: - Hover tracking

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        removeButton.isHidden = false
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        removeButton.isHidden = true
        layer?.backgroundColor = nil
    }

    // MARK: - Remove action

    @objc private func removeClicked() {
        onRemove?(item.id)
    }

    // MARK: - Drag source

    public override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let dx = currentPoint.x - startPoint.x
        let dy = currentPoint.y - startPoint.y
        let distance = sqrt(dx * dx + dy * dy)

        // Require minimum drag distance to avoid accidental drags
        guard distance > 4 else { return }
        dragStartPoint = nil // prevent re-triggering

        let fileURL = item.shelfURL
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Use the thumbnail image for drag feedback
        let dragImage = imageView.image ?? NSWorkspace.shared.icon(forFile: fileURL.path)
        let imageFrame = NSRect(origin: .zero, size: Self.thumbnailSize)
        draggingItem.setDraggingFrame(imageFrame, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    public override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
    }

    // MARK: - NSDraggingSource

    public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy, .move]
        case .withinApplication:
            return .move
        @unknown default:
            return .copy
        }
    }

    public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // If the file was moved out (not just copied), remove from shelf
        if operation == .move {
            onRemove?(item.id)
        }
    }
}
