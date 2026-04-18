import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI bridge around an AppKit drag source.
///
/// - When `useDirectURL` is `false` (default / local-copy mode): uses
///   `NSFilePromiseProvider` to hand files to Finder. The promise writer
///   being invoked is the "drop succeeded" signal used to remove the item from
///   the shelf, because `draggingSession(_:endedAt:operation:)` for promise
///   drags almost always reports `.copy` regardless of the receiver's actual
///   intent.
///
/// - When `useDirectURL` is `true` (reference mode): places the real file URL
///   directly on the drag pasteboard. Avoids the promise copy, which would
///   silently duplicate the file. In this mode `endedAt:operation:` is
///   reliable — `onDelivered` fires there for any non-empty operation.
@MainActor
public struct FileDragSourceView: NSViewRepresentable {
    public let url: URL
    /// When true the drag uses the direct-URL path (reference mode).
    public let useDirectURL: Bool
    /// Called after the file has been delivered to the receiver (drop
    /// succeeded). Caller decides whether to remove the item from the shelf.
    public let onDelivered: () -> Void

    public init(url: URL, useDirectURL: Bool = false, onDelivered: @escaping () -> Void) {
        self.url = url
        self.useDirectURL = useDirectURL
        self.onDelivered = onDelivered
    }

    public func makeNSView(context: Context) -> FileDragSourceNSView {
        let v = FileDragSourceNSView()
        v.url = url
        v.useDirectURL = useDirectURL
        v.onDelivered = onDelivered
        return v
    }

    public func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.url = url
        nsView.useDirectURL = useDirectURL
        nsView.onDelivered = onDelivered
    }
}

@MainActor
public final class FileDragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    public var url: URL = URL(fileURLWithPath: "/")
    public var useDirectURL: Bool = false
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
        if useDirectURL {
            // Reference mode: hand the real URL straight to the drag session.
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.draggingFrame = bounds
            beginDraggingSession(with: [item], event: event, source: self)
        } else {
            // Local-copy mode: use NSFilePromiseProvider so Finder never
            // touches our Application Support file directly (avoids -8058).
            let utType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
                ?? .data
            let provider = NSFilePromiseProvider(fileType: utType.identifier, delegate: self)
            provider.userInfo = url

            let item = NSDraggingItem(pasteboardWriter: provider)
            item.draggingFrame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

            beginDraggingSession(with: [item], event: event, source: self)
        }
    }

    // MARK: - NSDraggingSource

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Let the receiving app pick: Option → .copy, default → .move.
        return [.copy, .move, .generic]
    }

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // For reference-mode (direct URL) drags, `endedAt:operation:` is
        // reliable. Fire `onDelivered` on any successful operation.
        guard MainActor.assumeIsolated({ useDirectURL }) else { return }
        if !operation.isEmpty {
            Task { @MainActor [weak self] in
                self?.onDelivered()
            }
        }
    }

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
