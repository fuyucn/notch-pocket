import SwiftUI
import AppKit

@MainActor
public struct NotchPanelRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    private var targetSize: CGSize {
        switch viewModel.status {
        case .closed, .minimized:
            // Fully hidden when idle — don't render a visible pill under the notch.
            return .zero
        case .popping:
            let s = viewModel.geometry.preActivatedPanelSize
            return CGSize(width: s.width, height: s.height)
        case .opened:
            let s = viewModel.geometry.openedPanelSize
            return CGSize(width: s.width, height: s.height)
        }
    }

    private var targetTopRadius: CGFloat {
        switch viewModel.status {
        case .closed, .minimized: return NotchShape.closedTopRadius
        case .popping, .opened: return NotchShape.openedTopRadius
        }
    }

    private var targetBottomRadius: CGFloat {
        switch viewModel.status {
        case .closed, .minimized: return NotchShape.closedBottomRadius
        case .popping, .opened: return NotchShape.openedBottomRadius
        }
    }

    public var body: some View {
        ZStack {
            // Content
            content
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .background(
            NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius)
                .fill(Color.black)
        )
        .overlay(
            NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: viewModel.status)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .closed, .minimized:
            Color.clear
        case .popping:
            VStack(spacing: 0) {
                notchTopBar
                PreActivationBarView(
                    primaryFileName: viewModel.primaryFileName,
                    extraCount: viewModel.extraCount,
                    shelfCount: viewModel.shelfCount,
                    notchInset: 8
                )
            }
            .frame(
                width: viewModel.geometry.preActivatedPanelSize.width,
                height: viewModel.geometry.preActivatedPanelSize.height
            )
            .clipShape(NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius))
        case .opened:
            openedContent
        }
    }

    /// Horizontal strip at the very top of the panel that sits alongside the
    /// physical notch. Left shoulder: logo + title. Right shoulder: shelf-count
    /// badge (popping) or view-toggle + close buttons (opened).
    ///
    /// `opened` aligns the left/right shoulders with the content area
    /// (40pt horizontal padding on both sides). `popping` keeps the shoulders
    /// hugging the notch so the tiny pill looks balanced.
    @ViewBuilder
    private var notchTopBar: some View {
        let notchHeight = viewModel.geometry.notchRect?.height ?? 32
        let notchWidth = viewModel.geometry.notchRect?.width ?? 200
        let isOpened = viewModel.status == .opened
        HStack(spacing: 0) {
            // Left shoulder — logo + title
            HStack(spacing: 6) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Notch Pocket")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: isOpened ? .leading : .trailing)
            .padding(.leading, isOpened ? 40 : 0)
            .padding(.trailing, isOpened ? 0 : 10)
            // Reserve exact notch width so the left/right content ends up on
            // the notch's shoulders, not under the physical cutout.
            Color.clear.frame(width: notchWidth)
            // Right shoulder
            rightShoulder
                .frame(maxWidth: .infinity, alignment: isOpened ? .trailing : .leading)
                .padding(.leading, isOpened ? 0 : 10)
                .padding(.trailing, isOpened ? 40 : 0)
        }
        .frame(height: notchHeight)
    }

    @ViewBuilder
    private var rightShoulder: some View {
        switch viewModel.status {
        case .opened:
            HStack(spacing: 4) {
                let mode = viewModel.settingsManager?.shelfViewMode ?? .list
                Button(action: toggleViewMode) {
                    Image(systemName: mode == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        case .popping:
            if viewModel.shelfCount > 0 {
                Text("\(viewModel.shelfCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            } else {
                EmptyView()
            }
        case .closed, .minimized:
            EmptyView()
        }
    }

    private func toggleViewMode() {
        guard let settings = viewModel.settingsManager else { return }
        settings.shelfViewMode = (settings.shelfViewMode == .list) ? .thumbnail : .list
        viewModel.shelfRefreshToken &+= 1
    }

    private func close() {
        viewModel.requestClose()
    }

    @ViewBuilder
    private var openedContent: some View {
        if let shelfManager = viewModel.shelfManager {
            let size = viewModel.geometry.openedPanelSize
            let mode = viewModel.settingsManager?.shelfViewMode ?? .list
            VStack(spacing: 0) {
                notchTopBar
                contentBody(shelfManager: shelfManager, mode: mode)
                    .padding(.horizontal, 40)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius))
            .id(viewModel.shelfRefreshToken)
        } else {
            Text("Shelf unavailable")
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func contentBody(shelfManager: FileShelfManager, mode: ShelfViewMode) -> some View {
        HStack(spacing: 14) {
            let urls = shelfManager.items.compactMap { $0.resolvedURL() }
            AirDropActionView(
                isEnabled: true,  // always accept drag-to-airdrop; tap only active when shelf non-empty
                isDropTargeted: viewModel.isDragOverAirDrop,
                onTap: {
                    if !urls.isEmpty { AirDropService.share(urls: urls) }
                },
                onFrameChange: { [weak vm = viewModel] rect in
                    // rect is in global screen coords; convert to the panel's
                    // content-view coords (panel is top-anchored so Y flips).
                    // We store raw global rect; forwarder will convert drop
                    // points to global coords to compare.
                    vm?.airDropRectInPanel = rect
                }
            )
            let removeOnDragOut = viewModel.settingsManager?.removeOnDragOut ?? true
            switch mode {
            case .thumbnail:
                ShelfGridView(
                    items: shelfManager.items,
                    isDragInside: viewModel.isDragInside,
                    removeOnDragOut: removeOnDragOut,
                    onOpen: { item in
                        if let url = item.resolvedURL() { NSWorkspace.shared.open(url) }
                    },
                    onRemove: { [weak shelfManager] id in shelfManager?.removeItem(id) },
                    onRemoveAll: { [weak shelfManager] in shelfManager?.clearAll() }
                )
            case .list:
                ShelfListView(
                    items: shelfManager.items,
                    isDragInside: viewModel.isDragInside,
                    removeOnDragOut: removeOnDragOut,
                    onOpen: { item in
                        if let url = item.resolvedURL() { NSWorkspace.shared.open(url) }
                    },
                    onRemove: { [weak shelfManager] id in shelfManager?.removeItem(id) },
                    onRemoveAll: { [weak shelfManager] in shelfManager?.clearAll() }
                )
            }
        }
    }
}
