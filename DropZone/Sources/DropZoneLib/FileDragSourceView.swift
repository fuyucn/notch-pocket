import AppKit
import SwiftUI

/// SwiftUI bridge around an AppKit `NSDraggingSource` view for a single
/// shelf file. Starts a drag session on mouseDown, reports move/copy
/// (Option toggles copy), and tells the caller when the drag ends
/// successfully with `.move` so the shelf can remove the item.
@MainActor
public struct FileDragSourceView: NSViewRepresentable {
    public let url: URL
    public let onMoved: () -> Void

    public init(url: URL, onMoved: @escaping () -> Void) {
        self.url = url
        self.onMoved = onMoved
    }

    public func makeNSView(context: Context) -> FileDragSourceNSView {
        let v = FileDragSourceNSView()
        v.url = url
        v.onMoved = onMoved
        return v
    }

    public func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.url = url
        nsView.onMoved = onMoved
    }
}

@MainActor
public final class FileDragSourceNSView: NSView, NSDraggingSource {
    public var url: URL = URL(fileURLWithPath: "/")
    public var onMoved: () -> Void = {}

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) { nil }

    public override func mouseDown(with event: NSEvent) {
        // Only fire on actual drag, not plain click — AppKit handles this via
        // mouseDragged; but starting a drag session in mouseDown with a
        // synthesized drag item is the idiomatic pattern for click-and-drag.
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.draggingFrame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Option held ⇒ copy; otherwise move (with copy fallback).
        let optionDown = NSEvent.modifierFlags.contains(.option)
        return optionDown ? [.copy] : [.move, .copy]
    }

    nonisolated public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // Only remove from shelf if the receiver actually took a move.
        guard operation.contains(.move) else { return }
        Task { @MainActor [weak self] in
            self?.onMoved()
        }
    }
}
