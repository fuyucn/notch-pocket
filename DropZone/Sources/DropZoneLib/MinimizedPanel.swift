import AppKit
import Combine
import SwiftUI

/// Small borderless NSPanel that renders the `.minimized` capsule around the
/// notch. Its frame is sized to the capsule itself — nothing outside the
/// visible bar receives pointer events, so the menu bar and the rest of the
/// screen are never occluded. Drag-in continues to be handled by the main
/// NotchPanel.
@MainActor
public final class MinimizedPanel: NSPanel {
    public let viewModel: NotchViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var hostingView: NSHostingView<MinimizedBarView>?

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        let rect = Self.frame(for: viewModel.geometry)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // One level higher than popUpMenu so we render above the main NotchPanel
        // whenever both happen to be visible during a transition.
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = false

        let host = NSHostingView(rootView: Self.makeView(viewModel: viewModel, onTap: { [weak self] in
            self?.handleTap()
        }))
        host.frame = NSRect(origin: .zero, size: rect.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
        hostingView = host

        // Rebind SwiftUI whenever the shelf count changes, so the count badge
        // stays live.
        viewModel.$shelfCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebindView() }
            .store(in: &cancellables)

        // Track status to toggle visibility.
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncVisibility() }
            .store(in: &cancellables)

        syncVisibility()
    }

    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    /// Public so tests can force-sync without waiting for Combine dispatch.
    public func syncVisibility() {
        if viewModel.status == .minimized {
            setFrame(Self.frame(for: viewModel.geometry), display: true)
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    /// Re-render with current shelf count. Called on shelf updates and when
    /// geometry changes.
    public func rebindView() {
        hostingView?.rootView = Self.makeView(viewModel: viewModel, onTap: { [weak self] in
            self?.handleTap()
        })
    }

    /// Action fired by the SwiftUI tap gesture. Public so tests can simulate it.
    public func handleTap() {
        viewModel.markDropped()
    }

    public func updateGeometry(_ geometry: NotchGeometry) {
        viewModel.geometry = geometry
        setFrame(Self.frame(for: geometry), display: true)
        rebindView()
    }

    // MARK: - Layout

    private static func makeView(
        viewModel: NotchViewModel,
        onTap: @escaping () -> Void
    ) -> MinimizedBarView {
        let notchWidth = viewModel.geometry.notchRect?.width ?? 200
        let notchHeight = viewModel.geometry.notchRect?.height ?? MinimizedBarView.height
        return MinimizedBarView(
            shelfCount: viewModel.shelfCount,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            onTap: onTap
        )
    }

    private static func frame(for geometry: NotchGeometry) -> NSRect {
        let notchWidth = geometry.notchRect?.width ?? 200
        let notchMidX = geometry.notchRect?.midX ?? geometry.screenFrame.midX
        let notchHeight = geometry.notchRect?.height ?? MinimizedBarView.height
        let width = notchWidth + 2 * MinimizedBarView.shoulderWidth
        return NSRect(
            x: notchMidX - width / 2,
            y: geometry.screenFrame.maxY - notchHeight,
            width: width,
            height: notchHeight
        )
    }
}
