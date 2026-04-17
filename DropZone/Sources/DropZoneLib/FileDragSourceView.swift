import AppKit
import SwiftUI

/// SwiftUI bridge around an AppKit `NSDraggingSource` view for a single
/// shelf file. Starts a drag session on mouseDown. The shelf-side behavior
/// (remove on drag-out vs keep) is controlled by a settings lookup the
/// caller supplies, NOT by the Option key — Option is left to macOS's
/// standard copy/move semantics on the receiving side.
@MainActor
public struct FileDragSourceView: NSViewRepresentable {
    public let url: URL
    public let onDragEnded: (_ droppedSuccessfully: Bool) -> Void

    public init(url: URL, onDragEnded: @escaping (_ droppedSuccessfully: Bool) -> Void) {
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
public final class FileDragSourceNSView: NSView, NSDraggingSource {
    public var url: URL = URL(fileURLWithPath: "/")
    public var onDragEnded: (_ droppedSuccessfully: Bool) -> Void = { _ in }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) { nil }

    public override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.draggingFrame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Let the receiving app pick (copy/move). macOS maps Option → copy,
        // default → move for file URLs. We don't override this.
        return [.copy, .move, .generic]
    }

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // A successful drop has a non-empty operation; a cancelled drag is [].
        let accepted = !operation.isEmpty
        Task { @MainActor [weak self] in
            self?.onDragEnded(accepted)
        }
    }
}
