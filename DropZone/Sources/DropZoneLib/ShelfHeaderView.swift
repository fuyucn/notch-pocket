import SwiftUI

@MainActor
public struct ShelfHeaderView: View {
    public let itemCount: Int
    public let viewMode: ShelfViewMode
    public let onToggleView: () -> Void
    public let onMinimize: () -> Void

    public init(itemCount: Int, viewMode: ShelfViewMode, onToggleView: @escaping () -> Void, onMinimize: @escaping () -> Void) {
        self.itemCount = itemCount
        self.viewMode = viewMode
        self.onToggleView = onToggleView
        self.onMinimize = onMinimize
    }

    public var titleLabel: String {
        let noun = itemCount == 1 ? "item" : "items"
        return "\(itemCount) \(noun)"
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(titleLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(action: onToggleView) {
                Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onMinimize) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
