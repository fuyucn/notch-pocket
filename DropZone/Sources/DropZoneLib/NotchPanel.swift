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

        let rect = viewModel.geometry.hoverTriggerRect
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

        // Observe status to toggle click-through
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncIgnoresMouseEvents() }
            .store(in: &cancellables)

        // Observe mouse location from EventMonitors
        EventMonitors.shared.mouseLocation
            .combineLatest(EventMonitors.shared.isDragging)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point, dragging in
                guard let self else { return }
                self.viewModel.updateMouseLocation(point, isDragging: dragging)
            }
            .store(in: &cancellables)
    }

    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    /// Sync `ignoresMouseEvents` with current viewModel status.
    /// Public so tests can force-sync after synchronous model mutation
    /// (without waiting for Combine dispatch).
    public func syncIgnoresMouseEvents() {
        ignoresMouseEvents = (viewModel.status == .closed)
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        viewModel.geometry = geometry
        setFrame(geometry.hoverTriggerRect, display: true)
    }
}
