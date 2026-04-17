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
        case .closed:
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
        case .closed: return NotchShape.closedTopRadius
        case .popping, .opened: return NotchShape.openedTopRadius
        }
    }

    private var targetBottomRadius: CGFloat {
        switch viewModel.status {
        case .closed: return NotchShape.closedBottomRadius
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
        case .closed:
            Color.clear
        case .popping:
            PreActivationBarView(
                primaryFileName: viewModel.primaryFileName,
                extraCount: viewModel.extraCount,
                shelfCount: viewModel.shelfCount
            )
            .frame(
                width: viewModel.geometry.preActivatedPanelSize.width,
                height: viewModel.geometry.preActivatedPanelSize.height
            )
            .clipShape(NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius))
        case .opened:
            openedContent
        }
    }

    @ViewBuilder
    private var openedContent: some View {
        if let shelfManager = viewModel.shelfManager {
            let mode = viewModel.settingsManager?.shelfViewMode ?? .list
            let size = viewModel.geometry.openedPanelSize
            VStack(spacing: 0) {
                Spacer().frame(height: 36) // below notch cutout
                ShelfHeaderView(
                    itemCount: shelfManager.items.count,
                    viewMode: mode,
                    onToggleView: { [weak vm = viewModel] in
                        guard let vm, let settings = vm.settingsManager else { return }
                        settings.shelfViewMode = (settings.shelfViewMode == .list) ? .thumbnail : .list
                        vm.shelfRefreshToken &+= 1  // force SwiftUI re-read
                    },
                    onMinimize: { [weak vm = viewModel] in
                        vm?.forceClose()
                    }
                )
                Divider().background(Color.white.opacity(0.08))
                Group {
                    if mode == .list {
                        ShelfListView(
                            items: shelfManager.items,
                            onOpen: { item in NSWorkspace.shared.open(item.shelfURL) },
                            onRemove: { [weak shelfManager] id in shelfManager?.removeItem(id) }
                        )
                    } else {
                        ShelfContainerView(
                            shelfManager: shelfManager,
                            refreshToken: viewModel.shelfRefreshToken
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(topCornerRadius: targetTopRadius, bottomCornerRadius: targetBottomRadius))
            .id(viewModel.shelfRefreshToken) // cache-bust the whole sub-tree
        } else {
            Text("Shelf unavailable")
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
