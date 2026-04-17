import SwiftUI
import AppKit

/// A small pill-shaped SwiftUI view that, when pressed and dragged, starts a
/// native `NSDraggingSession` carrying every file in the shelf. macOS's
/// SwiftUI `.onDrag` only emits a single `NSItemProvider`, which drag-receivers
/// interpret as a single-file transfer — we need a true multi-item drag so
/// Finder and friends create one file per item. Bridging to AppKit via
/// `NSViewRepresentable` is the simplest path.
@MainActor
public struct AllDragHandle: View {
    public let items: [ShelfItem]
    public let onAllMoved: () -> Void

    public init(items: [ShelfItem], onAllMoved: @escaping () -> Void = {}) {
        self.items = items
        self.onAllMoved = onAllMoved
    }

    public var body: some View {
        MultiFileDragSourceView(urls: items.map { $0.shelfURL }, onMoved: onAllMoved)
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
    let onMoved: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let v = DragSourceNSView()
        v.urls = urls
        v.onMoved = onMoved
        return v
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.onMoved = onMoved
    }
}

/// AppKit view that begins a multi-file drag session on mouseDown.
@MainActor
private final class DragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onMoved: () -> Void = {}

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

        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
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
        let optionDown = NSEvent.modifierFlags.contains(.option)
        return optionDown ? [.copy] : [.move, .copy]
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        guard operation.contains(.move) else { return }
        Task { @MainActor [weak self] in
            self?.onMoved()
        }
    }
}
