import SwiftUI

@MainActor
public struct NotchPanelRootView: View {
    @ObservedObject var viewModel: NotchViewModel

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            switch viewModel.status {
            case .closed:
                Color.clear
            case .popping:
                poppingContent
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            case .opened:
                openedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.status)
        // Top-align so the sub-pills sit flush to the screen top and visually wrap the notch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var poppingContent: some View {
        let size = viewModel.geometry.preActivatedPanelSize
        PreActivationBarView(
            primaryFileName: viewModel.primaryFileName,
            extraCount: viewModel.extraCount,
            shelfCount: viewModel.shelfCount
        )
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    @ViewBuilder
    private var openedContent: some View {
        let size = viewModel.geometry.openedPanelSize
        Group {
            if let shelfManager = viewModel.shelfManager {
                ShelfContainerView(
                    shelfManager: shelfManager,
                    refreshToken: viewModel.shelfRefreshToken
                )
                .padding(.top, 40)   // leave room for the notch
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                Text("Shelf unavailable")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}
