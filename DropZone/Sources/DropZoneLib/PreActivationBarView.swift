import SwiftUI

/// Narrow pill shown for both the pre-activation-bar-during-drag case and the
/// minimized idle case (shelf has files, user isn't interacting). The same
/// popping frame is reused — only the inner content switches.
public struct PreActivationBarView: View {
    public let primaryFileName: String?
    public let extraCount: Int
    public let shelfCount: Int
    /// Sorted newest-first shelf items used to render tiny thumbnails in the
    /// idle variant. Empty / ignored in the drag variant.
    public let items: [ShelfItem]
    /// True while a file drag is live. Drives the content fork — "Drop here"
    /// when true, shelf summary otherwise.
    public let isFileDragging: Bool
    /// Vertical inset applied at the top so the content sits below the physical
    /// notch cutout (notch height + small padding). Defaults to 40 for previews.
    public let notchInset: CGFloat

    public static let empty = PreActivationBarView(
        primaryFileName: nil,
        extraCount: 0,
        shelfCount: 0,
        items: [],
        isFileDragging: false
    )

    public init(
        primaryFileName: String?,
        extraCount: Int,
        shelfCount: Int,
        items: [ShelfItem] = [],
        isFileDragging: Bool = true,
        notchInset: CGFloat = 40
    ) {
        self.primaryFileName = primaryFileName
        self.extraCount = extraCount
        self.shelfCount = shelfCount
        self.items = items
        self.isFileDragging = isFileDragging
        self.notchInset = notchInset
    }

    public var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: notchInset)
            if isFileDragging {
                dragContent
            } else {
                idleContent
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var dragContent: some View {
        Image(systemName: "tray.and.arrow.down.fill")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
        Text("Drop here")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
        if let name = primaryFileName {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 340)
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 4) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { _, item in
                    MiniThumb(item: item)
                }
                if items.count > 3 {
                    Text("+\(items.count - 3)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
            }
            Text("\(shelfCount)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
    }
}

private struct MiniThumb: View {
    let item: ShelfItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.08))
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 28, height: 28)
    }

    private var iconName: String {
        guard let ext = item.fileExtension?.lowercased() else { return "doc" }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff": return "photo"
        case "mp4", "mov", "m4v", "mkv": return "film"
        case "mp3", "m4a", "wav", "aac", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "7z": return "archivebox"
        case "txt", "md", "rtf": return "doc.text"
        default: return "doc"
        }
    }
}
