import AppKit

/// Displays the file shelf: a horizontally scrolling row of file thumbnails
/// with a clear-all button, shown inside the expanded DropZone panel.
@MainActor
public final class FileShelfView: NSView {
    // MARK: - Dependencies

    public var fileShelfManager: FileShelfManager? {
        didSet { reload() }
    }

    // MARK: - Callbacks

    /// Called when the shelf becomes empty (for auto-collapse).
    public var onShelfEmpty: (@MainActor () -> Void)?

    /// Called when items change (for updating count badge).
    public var onItemCountChanged: (@MainActor (Int) -> Void)?

    // MARK: - Layout constants

    private static let itemSpacing: CGFloat = 4
    private static let contentInsetX: CGFloat = 8
    private static let contentInsetY: CGFloat = 4
    private static let clearButtonWidth: CGFloat = 28

    // MARK: - Subviews

    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasHorizontalScroller = false
        sv.hasVerticalScroller = false
        sv.drawsBackground = false
        sv.horizontalScrollElasticity = .allowed
        sv.verticalScrollElasticity = .none
        sv.contentView.drawsBackground = false
        return sv
    }()

    private let contentView: NSView = {
        let v = NSView()
        v.wantsLayer = true
        return v
    }()

    private let clearAllButton: NSButton = {
        let button = NSButton()
        button.bezelStyle = .circular
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear all files")
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.image = image?.withSymbolConfiguration(config)
        button.contentTintColor = .white.withAlphaComponent(0.7)
        button.toolTip = "Clear all files"
        button.isHidden = true
        return button
    }()

    private let emptyLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Drop files here")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.4)
        label.alignment = .center
        return label
    }()

    // MARK: - State

    private var thumbnailViews: [FileThumbnailView] = []

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupSubviews() {
        wantsLayer = true

        scrollView.documentView = contentView
        addSubview(scrollView)

        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllClicked)
        addSubview(clearAllButton)

        addSubview(emptyLabel)
    }

    public override func layout() {
        super.layout()

        let clearBtnSize = Self.clearButtonWidth
        let hasItems = !thumbnailViews.isEmpty

        // Clear button on the right
        clearAllButton.frame = NSRect(
            x: bounds.maxX - clearBtnSize - 4,
            y: (bounds.height - clearBtnSize) / 2 + 2,
            width: clearBtnSize,
            height: clearBtnSize
        )

        // Scroll view fills remaining space
        let scrollWidth = hasItems ? bounds.width - clearBtnSize - 8 : bounds.width
        scrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollWidth,
            height: bounds.height
        )

        // Empty label centered
        emptyLabel.frame = bounds

        layoutItems()
    }

    // MARK: - Public API

    /// Reload the view from the shelf manager's current items.
    public func reload() {
        // Remove old thumbnails
        for view in thumbnailViews {
            view.removeFromSuperview()
        }
        thumbnailViews.removeAll()

        guard let manager = fileShelfManager else {
            updateEmptyState()
            return
        }

        // Create thumbnail views for each item
        for item in manager.items {
            let thumbnail = FileThumbnailView(item: item)
            thumbnail.onRemove = { [weak self] id in
                self?.removeItem(id)
            }
            contentView.addSubview(thumbnail)
            thumbnailViews.append(thumbnail)
        }

        updateEmptyState()
        layoutItems()
        onItemCountChanged?(manager.items.count)
    }

    /// Animate adding new items at the end.
    public func animateAddItems(_ newItems: [ShelfItem]) {
        for item in newItems {
            let thumbnail = FileThumbnailView(item: item)
            thumbnail.onRemove = { [weak self] id in
                self?.removeItem(id)
            }
            thumbnail.alphaValue = 0
            contentView.addSubview(thumbnail)
            thumbnailViews.append(thumbnail)
        }

        updateEmptyState()
        layoutItems()

        // Fade in new items
        let newStartIndex = thumbnailViews.count - newItems.count
        for i in newStartIndex..<thumbnailViews.count {
            let view = thumbnailViews[i]
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = 1
            }
        }

        // Scroll to show newest item
        if let last = thumbnailViews.last {
            scrollView.contentView.scrollToVisible(last.frame)
        }

        onItemCountChanged?(thumbnailViews.count)
    }

    /// Animate removing an item.
    public func animateRemoveItem(_ id: UUID) {
        guard let index = thumbnailViews.firstIndex(where: { $0.item.id == id }) else { return }
        let view = thumbnailViews[index]

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            view.animator().alphaValue = 0
            view.animator().frame = view.frame.offsetBy(dx: 0, dy: -10)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                view.removeFromSuperview()
                self?.thumbnailViews.removeAll(where: { $0.item.id == id })
                self?.layoutItems()
                self?.updateEmptyState()
                self?.onItemCountChanged?(self?.thumbnailViews.count ?? 0)

                if self?.thumbnailViews.isEmpty == true {
                    self?.onShelfEmpty?()
                }
            }
        })
    }

    // MARK: - Private

    private func removeItem(_ id: UUID) {
        fileShelfManager?.removeItem(id)
        animateRemoveItem(id)
    }

    @objc private func clearAllClicked() {
        // Animate all items fading out
        let views = thumbnailViews
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for view in views {
                view.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.fileShelfManager?.clearAll()
                for view in views {
                    view.removeFromSuperview()
                }
                self?.thumbnailViews.removeAll()
                self?.updateEmptyState()
                self?.onItemCountChanged?(0)
                self?.onShelfEmpty?()
            }
        })
    }

    private func layoutItems() {
        var x = Self.contentInsetX
        let y = Self.contentInsetY

        for view in thumbnailViews {
            view.frame = NSRect(
                origin: NSPoint(x: x, y: y),
                size: FileThumbnailView.itemSize
            )
            x += FileThumbnailView.itemSize.width + Self.itemSpacing
        }

        // Update content view size for scrolling
        let totalWidth = max(x + Self.contentInsetX, scrollView.bounds.width)
        contentView.frame = NSRect(
            x: 0,
            y: 0,
            width: totalWidth,
            height: scrollView.bounds.height
        )
    }

    private func updateEmptyState() {
        let isEmpty = thumbnailViews.isEmpty
        emptyLabel.isHidden = !isEmpty
        clearAllButton.isHidden = isEmpty
        scrollView.isHidden = isEmpty
    }
}
