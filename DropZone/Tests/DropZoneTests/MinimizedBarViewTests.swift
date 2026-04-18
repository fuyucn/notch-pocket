import Testing
import AppKit
import SwiftUI
@testable import DropZoneLib

struct MinimizedBarViewTests {
    @Test @MainActor
    func rendersWithZeroCount() {
        let view = MinimizedBarView(shelfCount: 0, notchWidth: 200, onTap: {})
        // Host it so SwiftUI evaluates the body.
        let hosting = NSHostingView(rootView: view)
        #expect(hosting.fittingSize.width > 0)
    }

    @Test @MainActor
    func rendersWithLargeCount() {
        let view = MinimizedBarView(shelfCount: 99, notchWidth: 200, onTap: {})
        let hosting = NSHostingView(rootView: view)
        #expect(hosting.fittingSize.width > 0)
    }

    @Test @MainActor
    func onTapFiresCallback() {
        var fired = false
        let view = MinimizedBarView(shelfCount: 1, notchWidth: 200, onTap: { fired = true })
        view.onTap()
        #expect(fired)
    }
}
