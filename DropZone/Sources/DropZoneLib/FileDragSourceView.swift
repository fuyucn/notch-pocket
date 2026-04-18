import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI bridge around an AppKit drag source that uses
/// `NSFilePromiseProvider` to hand files out to Finder / other apps.
///
/// Why a promise instead of `url as NSURL`:
/// - AppKit lets the receiving app choose `.copy` or `.move` based on the
///   Option key. If we hand over the real shelf URL, Finder may try to
///   rename/unlink our source (producing `NSFileWriteUnknownError` -8058
///   in `~/Library/Application Support`). With a promise, AppKit calls back
///   with a URL inside the destination's scratch directory and we copy into
///   that — Finder never touches our source file.
/// - We still learn whether the drop ultimately resolved as copy or move
///   (via `draggingSession:endedAt:operation:`), which lets the caller
///   decide whether to keep the shelf item around.
@MainActor
public struct FileDragSourceView: NSViewRepresentable {
    public let url: URL
    /// Called on drop-end. `operation` is the final resolution (`.move`,
    /// `.copy`, `.generic`, or `[]` when cancelled). Caller decides whether
    /// to remove the item from the shelf based on settings.
    public let onDragEnded: (_ operation: NSDragOperation) -> Void

    public init(url: URL, onDragEnded: @escaping (_ operation: NSDragOperation) -> Void) {
        self.url = url
        self.onDragEnded = onDragEnded
    }

    public func makeNSView(context: Context) -> FileDragSourceNSView {
        let v = FileDragSourceNSView()
        v.url = url
        v.onDragEnded = onDragEnded
        return v
    }

    public func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.url = url
        nsView.onDragEnded = onDragEnded
    }
}

@MainActor
public final class FileDragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    public var url: URL = URL(fileURLWithPath: "/")
    public var onDragEnded: (_ operation: NSDragOperation) -> Void = { _ in }

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

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        Task { @MainActor [weak self] in
            self?.onDragEnded(operation)
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
            // If AppKit pre-created an empty placeholder at the destination,
            // remove it so copyItem can succeed.
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: src, to: url)
            completionHandler(nil)
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
