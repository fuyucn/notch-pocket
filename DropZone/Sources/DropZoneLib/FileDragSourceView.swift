import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI bridge around an AppKit drag source that uses
/// `NSFilePromiseProvider` to hand files out to Finder / other apps.
///
/// The receiver (Finder etc.) asks us for the file *only* when the drop is
/// accepted — so `filePromiseProvider(_:writePromiseTo:...)` being invoked
/// at all is our "drop succeeded" signal. That's the trigger we use to
/// remove from the shelf (if the user's setting says so), because
/// `draggingSession(_:endedAt:operation:)` for promise drags almost always
/// reports `.copy` regardless of the receiver's actual intent.
@MainActor
public struct FileDragSourceView: NSViewRepresentable {
    public let url: URL
    /// Called from the promise writer after the file has been delivered to
    /// the receiver (i.e. drop succeeded). Caller decides whether to remove
    /// the item from the shelf.
    public let onDelivered: () -> Void

    public init(url: URL, onDelivered: @escaping () -> Void) {
        self.url = url
        self.onDelivered = onDelivered
    }

    public func makeNSView(context: Context) -> FileDragSourceNSView {
        let v = FileDragSourceNSView()
        v.url = url
        v.onDelivered = onDelivered
        return v
    }

    public func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.url = url
        nsView.onDelivered = onDelivered
    }
}

@MainActor
public final class FileDragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    public var url: URL = URL(fileURLWithPath: "/")
    public var onDelivered: () -> Void = {}

    /// Queue the promise provider uses to perform file I/O off the main thread.
    private let ioQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) { nil }

    public override func mouseDown(with event: NSEvent) {
        let utType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        let provider = NSFilePromiseProvider(fileType: utType.identifier, delegate: self)
        provider.userInfo = url

        let item = NSDraggingItem(pasteboardWriter: provider)
        item.draggingFrame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Let the receiving app pick: Option → .copy, default → .move.
        return [.copy, .move, .generic]
    }

    // NSDraggingSource endedAt:operation: is intentionally not used for
    // shelf removal — see the note above. We rely on the promise writer
    // being invoked.

    // MARK: - NSFilePromiseProviderDelegate

    nonisolated public func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        (filePromiseProvider.userInfo as? URL)?.lastPathComponent ?? "file"
    }

    nonisolated public func filePromiseProvider(
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
                self?.onDelivered()
            }
        } catch {
            completionHandler(error)
        }
    }

    nonisolated public func operationQueue(
        for filePromiseProvider: NSFilePromiseProvider
    ) -> OperationQueue {
        // Read MainActor-only property once via a hop, then return.
        // We can't await here; ioQueue is set at init and never mutated.
        return MainActor.assumeIsolated { ioQueue }
    }
}
