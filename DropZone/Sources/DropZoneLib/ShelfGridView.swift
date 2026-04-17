import SwiftUI

@MainActor
public struct ShelfGridView: View {
    public let items: [ShelfItem]
    public let onOpen: (ShelfItem) -> Void
    public let onRemove: (UUID) -> Void

    public init(items: [ShelfItem], onOpen: @escaping (ShelfItem) -> Void, onRemove: @escaping (UUID) -> Void) {
        self.items = items
        self.onOpen = onOpen
        self.onRemove = onRemove
    }

    public var sortedItems: [ShelfItem] {
        items.sorted { $0.addedAt > $1.addedAt }
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            if items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Drop files here")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedItems) { item in
                            ShelfGridCell(
                                item: item,
                                onOpen: { onOpen(item) },
                                onRemove: { onRemove(item.id) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct ShelfGridCell: View {
    let item: ShelfItem
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .transition(.opacity)
                }
            }
            .frame(width: 60, height: 60)
            Text(item.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 86)
        }
        .frame(width: 90)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Remove", role: .destructive) { onRemove() }
        }
        .onTapGesture(count: 2) { onOpen() }
    }

    /// Generic icon by file extension — keep it simple; QuickLook/FileThumbnailView
    /// integration via NSViewRepresentable is a polish follow-up.
    private var iconName: String {
        guard let ext = item.fileExtension?.lowercased() else { return "doc" }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff":
            return "photo"
        case "mp4", "mov", "m4v", "mkv":
            return "film"
        case "mp3", "m4a", "wav", "aac", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "7z":
            return "archivebox"
        case "txt", "md", "rtf":
            return "doc.text"
        default:
            return "doc"
        }
    }
}
