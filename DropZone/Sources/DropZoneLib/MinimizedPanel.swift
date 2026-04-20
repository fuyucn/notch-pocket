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
        let geo = viewModel.geometry
        let notchWidth = geo.notchRect?.width ?? geo.fallbackNotchSize?.width ?? 200
        return MinimizedBarView(
            shelfCount: viewModel.shelfCount,
            notchWidth: notchWidth,
            notchHeight: capsuleHeight(for: geo),
            onTap: onTap
        )
    }

    private static func frame(for geometry: NotchGeometry) -> NSRect {
        let notchWidth = geometry.notchRect?.width ?? geometry.fallbackNotchSize?.width ?? 200
        let notchMidX = geometry.notchRect?.midX ?? geometry.screenFrame.midX
        let height = capsuleHeight(for: geometry)
        // Shoulder width is proportional to capsule height — matches the
        // scaling done inside MinimizedBarView.body.
        let shoulderWidth = height * 1.2
        let width = notchWidth + 2 * shoulderWidth
        return NSRect(
            x: notchMidX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Capsule vertical size: match the menu bar height of the current
    /// screen. On a notched display this equals the real notch height;
    /// on a non-notched display this is the standard 24pt menu-bar area.
    /// Falls back to NSStatusBar.system.thickness if visibleFrame isn't
    /// useful (e.g. under screen capture, full-screen app).
    private static func capsuleHeight(for geometry: NotchGeometry) -> CGFloat {
        if let notch = geometry.notchRect {
            return notch.height
        }
        // Derive menu-bar height from screen geometry: the area occupied
        // above `visibleFrame` is the menu bar.
        let menuBarHeight: CGFloat
        if let screen = NSScreen.screens.first(where: { $0.frame == geometry.screenFrame }) {
            menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        } else {
            menuBarHeight = 0
        }
        return menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness
    }
}
