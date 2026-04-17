import SwiftUI
import AppKit

@MainActor
public struct AirDropActionView: View {
    public let isEnabled: Bool
    /// Target side length. The view renders as a square of this size.
    public let size: CGFloat
    public let onTap: () -> Void
    /// Invoked when a file is dragged-and-dropped directly onto this button.
    /// Caller is responsible for kicking off AirDrop with the URLs (so the
    /// files bypass the shelf entirely).
    public let onDropFiles: ([URL]) -> Void

    public init(
        isEnabled: Bool,
        size: CGFloat = 86,
        onTap: @escaping () -> Void,
        onDropFiles: @escaping ([URL]) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.size = size
        self.onTap = onTap
        self.onDropFiles = onDropFiles
    }

    @State private var isDropTargeted: Bool = false

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.forward")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                Text("AirDrop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.34, blue: 0.36)
                        .opacity(isEnabled ? (isDropTargeted ? 1.0 : 0.90) : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.white.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { @MainActor in
                let urls = await Self.resolveFileURLs(from: providers)
                if !urls.isEmpty {
                    onDropFiles(urls)
                }
            }
            return true
        }
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    /// Load file URLs from a set of NSItemProviders. Serial to keep Swift 6
    /// concurrency happy with NSItemProvider (non-Sendable).
    @MainActor
    private static func resolveFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var result: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier("public.file-url") else { continue }
            let url: URL? = await withCheckedContinuation { cont in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    cont.resume(returning: url)
                }
            }
            if let url { result.append(url) }
        }
        return result
    }
}
