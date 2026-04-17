import SwiftUI
import AppKit

@MainActor
public struct ShelfListRowView: View {
    public let item: ShelfItem
    public let onOpen: () -> Void
    public let onRemove: () -> Void

    @State private var isHovering = false

    public init(item: ShelfItem, onOpen: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.item = item
        self.onOpen = onOpen
        self.onRemove = onRemove
    }

    public var tags: [String] {
        var result: [String] = []
        if let app = item.sourceAppName, !app.isEmpty { result.append(app) }
        if let ext = item.fileExtension, !ext.isEmpty { result.append(ext.uppercased()) }
        if item.fileSize > 0 { result.append(Self.formatSize(item.fileSize)) }
        return result
    }

    private static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ageString(item.addedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white.opacity(0.9), Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .onDrag {
            makeFileItemProvider(for: item.shelfURL)
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Remove", role: .destructive) { onRemove() }
        }
    }

    private func ageString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
