import AppKit
import SwiftUI

/// SwiftUI wrapper around the AppKit `FileShelfView`. Injects the shelf manager
/// and reloads the view when the SwiftUI state changes.
@MainActor
public struct ShelfContainerView: NSViewRepresentable {
    public let shelfManager: FileShelfManager
    /// Changes to this value trigger a reload on the underlying NSView.
    public let refreshToken: Int

    public init(shelfManager: FileShelfManager, refreshToken: Int) {
        self.shelfManager = shelfManager
        self.refreshToken = refreshToken
    }

    public func makeNSView(context: Context) -> FileShelfView {
        let view = FileShelfView()
        view.fileShelfManager = shelfManager
        view.reload()
        return view
    }

    public func updateNSView(_ nsView: FileShelfView, context: Context) {
        // Re-assign manager in case it changed; `didSet` on fileShelfManager reloads.
        nsView.fileShelfManager = shelfManager
        nsView.reload()
    }
}
