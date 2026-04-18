import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A small pill-shaped SwiftUI view that, when pressed and dragged, starts a
/// native `NSDraggingSession` carrying every shelf file.
///
/// - If **all** items are reference-mode, the real file URLs are placed
///   directly on the drag session. `endedAt:operation:` is reliable in this
///   case.
/// - If **any** item is local-copy mode, all items go through
///   `NSFilePromiseProvider` to avoid -8058. The promise writer being
///   invoked is the success signal.
/// - Items whose `resolvedURL()` is nil are silently skipped.
@MainActor
public struct AllDragHandle: View {
    public let items: [ShelfItem]
    /// Called once after every file in the drag has been delivered to the
    /// receiver. Caller decides shelf-side behavior (remove all / keep).
    public let onAllDelivered: () -> Void

    public init(
        items: [ShelfItem],
        onAllDelivered: @escaping () -> Void = {}
    ) {
        self.items = items
        self.onAllDelivered = onAllDelivered
    }

    public var body: some View {
        MultiFileDragSourceView(
            items: items,
            onAllDelivered: onAllDelivered
        )
        .frame(width: 44, height: 22)
        .overlay(
            HStack(spacing: 0) {
                Text("All")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .allowsHitTesting(false)
        )
        .background(
            Capsule().fill(Color.white.opacity(0.18))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}

@MainActor
private struct MultiFileDragSourceView: NSViewRepresentable {
    let items: [ShelfItem]
    let onAllDelivered: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let v = DragSourceNSView()
        v.items = items
        v.onAllDelivered = onAllDelivered
        return v
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.items = items
        nsView.onAllDelivered = onAllDelivered
    }
}

@MainActor
private final class DragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var items: [ShelfItem] = []
    var onAllDelivered: () -> Void = {}
    /// Bumped on each successful `writePromiseTo`. When it matches the
    /// current session's expected count, we fire `onAllDelivered` once.
    private var deliveredCount: Int = 0
    private var expectedCount: Int = 0
    /// Whether the current session uses direct URLs (all reference) or
    /// the promise path (any local-copy).
    private var sessionUsesDirectURL: Bool = false

    private let ioQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        // Resolve each item, skipping any whose file is gone.
        let resolved: [(item: ShelfItem, url: URL)] = items.compactMap { item in
            guard let url = item.resolvedURL() else { return nil }
            return (item, url)
        }
        guard !resolved.isEmpty else {
            super.mouseDown(with: event)
            return
        }

        deliveredCount = 0
        expectedCount = resolved.count

        // Use direct URLs only when every resolved item is a reference.
        let allReference = resolved.allSatisfy { $0.item.storage.isReference }
        sessionUsesDirectURL = allReference

        let draggingItems: [NSDraggingItem]
        if allReference {
            draggingItems = resolved.map { (_, url) in
                let di = NSDraggingItem(pasteboardWriter: url as NSURL)
                di.draggingFrame = NSRect(x: 0, y: 0, width: 32, height: 32)
                return di
            }
        } else {
            draggingItems = resolved.map { (_, url) in
                let utType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                    ?? UTType(filenameExtension: url.pathExtension)
                    ?? .data
                let provider = NSFilePromiseProvider(fileType: utType.identifier, delegate: self)
                provider.userInfo = url
                let di = NSDraggingItem(pasteboardWriter: provider)
                di.draggingFrame = NSRect(x: 0, y: 0, width: 32, height: 32)
                return di
            }
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return [.copy, .move, .generic]
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // For all-reference sessions, use `endedAt:operation:` as the
        // delivery signal instead of the promise path.
        guard MainActor.assumeIsolated({ sessionUsesDirectURL }) else { return }
        if !operation.isEmpty {
            Task { @MainActor [weak self] in
                self?.onAllDelivered()
            }
        }
    }

    // MARK: - NSFilePromiseProviderDelegate

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        (filePromiseProvider.userInfo as? URL)?.lastPathComponent ?? "file"
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let src = filePromiseProvider.userInfo as? URL else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: src, to: url)
            completionHandler(nil)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deliveredCount += 1
                if self.deliveredCount >= self.expectedCount {
                    self.onAllDelivered()
                }
            }
        } catch {
            completionHandler(error)
        }
    }

    nonisolated func operationQueue(
        for filePromiseProvider: NSFilePromiseProvider
    ) -> OperationQueue {
        return MainActor.assumeIsolated { ioQueue }
    }
}
