import AppKit
import UniformTypeIdentifiers

/// Build a correctly-typed `NSItemProvider` for dragging a shelf file out to
/// Finder/apps.
///
/// `NSItemProvider(contentsOf:)` tries to *read* the file into the provider,
/// which breaks for:
///   - `.app` bundles (directories) — the provider reads the directory
///     itself and the receiving app gets an inconsistent UTI.
///   - plain-text files (e.g. Markdown) — the receiver falls back to
///     `public.plain-text`/`public.data` and names the dropped file with the
///     UTI's localized description instead of the original filename.
///
/// Using `registerFileRepresentation(forTypeIdentifier:)` with the file's
/// actual UTI and the raw file URL tells AppKit "this is a reference to a
/// real file on disk of type X; the name is the URL's lastPathComponent".
/// Finder and friends then drop a copy named exactly like the source.
@MainActor
func makeFileItemProvider(for url: URL) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = url.lastPathComponent

    let resolvedType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        ?? UTType(filenameExtension: url.pathExtension)
        ?? (url.hasDirectoryPath ? .folder : .data)

    // `.open` so Finder does a normal copy (not a substituted "open in this app" flow).
    let options = NSItemProviderFileOptions.openInPlace
    _ = provider  // silence unused local warning if we only use register…
    provider.registerFileRepresentation(
        forTypeIdentifier: resolvedType.identifier,
        fileOptions: options,
        visibility: .all
    ) { completion in
        // Hand back the URL in-place; AppKit copies from disk.
        completion(url, true, nil)
        return nil
    }
    return provider
}
