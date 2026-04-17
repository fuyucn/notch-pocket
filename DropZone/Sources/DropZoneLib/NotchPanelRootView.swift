import SwiftUI

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
        case .opened:
            if let shelfManager = viewModel.shelfManager {
                ShelfContainerView(
                    shelfManager: shelfManager,
                    refreshToken: viewModel.shelfRefreshToken
                )
                .padding(.top, 40)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                Text("Shelf unavailable")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
