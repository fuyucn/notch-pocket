import AppKit

/// Build an `NSItemProvider` suitable for dragging a shelf file URL out to
/// Finder and other apps.
///
/// We deliberately avoid `NSItemProvider(contentsOf:)`, which tries to *read*
/// the file into the provider:
///   - For `.app` bundles (directories) the provider reads the directory and
///     drops end up as inconsistent items.
///   - For plain-text files (e.g. `.md`) the receiver falls back to
///     `public.plain-text`/`public.data` and renames the dropped file to the
///     UTI's localized description (e.g. "Markdown text file.md").
///
/// Wrapping an `NSURL` as the backing object instead registers the item as a
/// plain file-URL reference — pasteboard consumers (Finder, Mail, etc.) see
/// `public.file-url` plus the URL's `lastPathComponent` and copy the file
/// with its original name and any bundle contents intact.
@MainActor
func makeFileItemProvider(for url: URL) -> NSItemProvider {
    NSItemProvider(object: url as NSURL)
}
