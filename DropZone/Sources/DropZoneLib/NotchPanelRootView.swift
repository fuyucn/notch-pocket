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
        PreActivationBarView(
            primaryFileName: viewModel.primaryFileName,
            extraCount: viewModel.extraCount,
            shelfCount: viewModel.shelfCount
        )
        .frame(width: NotchGeometry.preActivatedSize.width, height: NotchGeometry.preActivatedSize.height)
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
        OpenedShelfPlaceholderView()
            .frame(width: NotchGeometry.shelfExpandedSize.width, height: NotchGeometry.shelfExpandedSize.height)
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

private struct OpenedShelfPlaceholderView: View {
    var body: some View {
        VStack {
            Spacer().frame(height: 40)   // visual breathing room below notch
            Text("Shelf")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Drop files here")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
    }
}
