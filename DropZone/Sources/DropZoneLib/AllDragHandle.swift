import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A small pill-shaped SwiftUI view that, when pressed and dragged, starts a
/// native `NSDraggingSession` carrying every shelf file as an
/// `NSFilePromiseProvider`. The promise mechanism avoids -8058 by ensuring
/// Finder never operates on our shelf file directly — instead AppKit calls
/// us back with a scratch URL that we copy into.
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
            urls: items.map { $0.shelfURL },
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
    let urls: [URL]
    let onAllDelivered: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let v = DragSourceNSView()
        v.urls = urls
        v.onAllDelivered = onAllDelivered
        return v
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.onAllDelivered = onAllDelivered
    }
}

@MainActor
private final class DragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var urls: [URL] = []
    var onAllDelivered: () -> Void = {}
    /// Bumped on each successful `writePromiseTo`. When it matches the
    /// current session's expected count, we fire `onAllDelivered` once.
    private var deliveredCount: Int = 0
    private var expectedCount: Int = 0

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
        guard !urls.isEmpty else {
            super.mouseDown(with: event)
            return
        }

        deliveredCount = 0
        expectedCount = urls.count

        let items = urls.map { url -> NSDraggingItem in
            let utType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
                ?? .data
            let provider = NSFilePromiseProvider(fileType: utType.identifier, delegate: self)
            provider.userInfo = url
            let item = NSDraggingItem(pasteboardWriter: provider)
            item.draggingFrame = NSRect(x: 0, y: 0, width: 32, height: 32)
            return item
        }

        beginDraggingSession(with: items, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return [.copy, .move, .generic]
    }

    // endedAt:operation: intentionally unused — see FileDragSourceView.

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
