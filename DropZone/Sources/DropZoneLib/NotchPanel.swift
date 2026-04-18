import AppKit
import Combine
import SwiftUI

@MainActor
public final class NotchPanel: NSPanel {
    public let viewModel: NotchViewModel
    private var cancellables: Set<AnyCancellable> = []
    public private(set) var dropForwarder: NotchDropForwarder?

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel

        // Window container must be tall enough for the largest UI state
        // (opened shelf) plus shadow margin. hoverTriggerRect is only 200pt
        // tall which is enough for click/drag detection but NOT enough to
        // contain the opened shelf SwiftUI tree — content would draw outside
        // the NSHostingView frame.
        let rect = Self.containerFrame(for: viewModel.geometry)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false

        // Click-through in the idle state
        ignoresMouseEvents = true

        let container = NSView(frame: rect)
        container.autoresizingMask = [.width, .height]

        let host = NSHostingView(rootView: NotchPanelRootView(viewModel: viewModel))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let forwarder = NotchDropForwarder(frame: container.bounds)
        forwarder.autoresizingMask = [.width, .height]
        container.addSubview(forwarder)
        self.dropForwarder = forwarder

        contentView = container

        setFrame(rect, display: false)
        orderFrontRegardless()

        // Observe status to toggle click-through + make-key for click-outside-to-close
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.syncIgnoresMouseEvents()
                if status == .opened {
                    self.makeKey()
                } else if self.isKeyWindow {
                    self.resignKey()
                }
            }
            .store(in: &cancellables)

        // When the user clicks outside the panel, the panel loses key status
        // and we dismiss the opened shelf. `.closed` and `.popping` never hold
        // key so this only fires on opened → click-outside.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.viewModel.status == .opened {
                    self.viewModel.requestClose()
                }
            }
        }

        // No global mouse monitor needed: drag-in activation is driven by
        // NotchDropForwarder's NSDraggingDestination callbacks (which fire
        // without any TCC permission because they're scoped to our own
        // window). Click-outside-to-close runs off `NSWindow.didResignKey`.
    }

    // Only allow key-status when the shelf is opened; otherwise the panel
    // stays non-key and non-activating (no focus stealing while idle).
    override public var canBecomeKey: Bool { viewModel.status == .opened }
    override public var canBecomeMain: Bool { false }

    /// Sync `ignoresMouseEvents` with current viewModel status.
    /// Public so tests can force-sync after synchronous model mutation
    /// (without waiting for Combine dispatch).
    public func syncIgnoresMouseEvents() {
        ignoresMouseEvents = (viewModel.status == .closed)
        // Hide the drop forwarder overlay when the panel shows interactive
        // content (opened shelf) so taps reach the SwiftUI root view. For
        // popping — which doubles as a tappable "minimized" indicator when
        // the shelf has items — we also hide it so the tap gesture on the
        // SwiftUI root fires. Drag-in still works because the hover rect
        // and .opened transition are driven by the main panel drop
        // destination, not this overlay.
        dropForwarder?.isHidden = (viewModel.status == .opened)
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        viewModel.geometry = geometry
        setFrame(Self.containerFrame(for: geometry), display: true)
    }

    /// Window rect that comfortably contains every state (closed, popping,
    /// opened) plus shadow/animation room. Top-anchored to screen, width
    /// matches hoverTriggerRect (which is the drag-detection area).
    private static func containerFrame(for geometry: NotchGeometry) -> NSRect {
        let hover = geometry.hoverTriggerRect
        let neededHeight = max(hover.height, geometry.openedPanelSize.height + 60)
        return NSRect(
            x: hover.origin.x,
            y: geometry.screenFrame.maxY - neededHeight,
            width: hover.width,
            height: neededHeight
        )
    }
}
