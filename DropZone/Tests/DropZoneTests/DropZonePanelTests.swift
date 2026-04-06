import Testing
import AppKit
@testable import DropZoneLib

@Suite("DropZonePanel Tests")
@MainActor
struct DropZonePanelTests {

    private func makeTestGeometry(hasNotch: Bool) -> NotchGeometry {
        if hasNotch {
            let notchRect = NSRect(x: 700, y: 1390, width: 200, height: 32)
            return NotchGeometry(
                notchRect: notchRect,
                activationZone: NSRect(x: 680, y: 1350, width: 240, height: 72),
                screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
                hasNotch: true
            )
        } else {
            return NotchGeometry(
                notchRect: nil,
                activationZone: NSRect(x: 840, y: 1008, width: 240, height: 72),
                screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                hasNotch: false
            )
        }
    }

    // MARK: - Creation

    @Test("Panel creation with notch starts hidden")
    func creationWithNotch() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        #expect(panel.panelState == .hidden)
        #expect(panel.geometry.hasNotch == true)
    }

    @Test("Panel creation without notch starts hidden")
    func creationWithoutNotch() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: false))
        #expect(panel.panelState == .hidden)
        #expect(panel.geometry.hasNotch == false)
    }

    // MARK: - Panel properties

    @Test("Panel is borderless with correct style mask")
    func panelIsBorderless() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.fullSizeContentView))
    }

    @Test("Panel is floating above all other windows")
    func panelIsFloating() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        #expect(panel.isFloatingPanel)
        // Panel should be above the shielding window level
        #expect(panel.level.rawValue > Int(CGShieldingWindowLevel()))
    }

    @Test("Panel is transparent with clear background")
    func panelIsTransparent() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
    }

    @Test("Panel can become key but not main")
    func panelCanBecomeKeyNotMain() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test("Panel does not hide on deactivate")
    func panelDoesNotHideOnDeactivate() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        #expect(!panel.hidesOnDeactivate)
    }

    // MARK: - State transitions

    @Test("enterListening transitions from hidden to listening")
    func enterListening() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.enterListening()
        #expect(panel.panelState == .listening)
    }

    @Test("enterListening is idempotent when already listening")
    func enterListeningOnlyFromHidden() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.enterListening()
        panel.enterListening()
        #expect(panel.panelState == .listening)
    }

    @Test("hide resets state and alpha")
    func hide() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.enterListening()
        panel.hide()
        #expect(panel.panelState == .hidden)
        #expect(panel.alphaValue == 0)
    }

    @Test("expand sets state to expanded")
    func expandSetsState() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand()
        #expect(panel.panelState == .expanded)
    }

    @Test("expand is idempotent")
    func expandIsIdempotent() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand()
        panel.expand()
        #expect(panel.panelState == .expanded)
    }

    @Test("collapse from non-expanded calls completion immediately")
    func collapseFromNonExpandedCallsCompletion() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        // Panel is hidden (not expanded), so collapse should call completion synchronously
        // Use nonisolated(unsafe) to satisfy Swift 6 Sendable closure requirement
        // since we know this executes synchronously on the same actor
        nonisolated(unsafe) var completed = false
        panel.collapse { completed = true }
        #expect(completed, "Completion should fire immediately when not expanded")
    }

    // MARK: - Shelf expanded state

    @Test("expandShelf sets state to shelfExpanded")
    func expandShelfSetsState() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expandShelf()
        #expect(panel.panelState == .shelfExpanded)
    }

    @Test("expandShelf is idempotent")
    func expandShelfIdempotent() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expandShelf()
        panel.expandShelf()
        #expect(panel.panelState == .shelfExpanded)
    }

    @Test("collapse works from shelfExpanded state")
    func collapseFromShelfExpanded() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expandShelf()
        #expect(panel.panelState == .shelfExpanded)
        // collapse starts animation; it should set state to .collapsed
        panel.collapse()
        #expect(panel.panelState == .collapsed)
    }

    @Test("shelfExpanded panel has correct size")
    func shelfExpandedSize() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expandShelf()
        let expectedSize = DropZonePanel.shelfExpandedSize
        #expect(panel.frame.size.width == expectedSize.width)
        #expect(panel.frame.size.height == expectedSize.height)
    }

    // MARK: - File count badge

    @Test("updateBadge creates badge layer")
    func updateBadgeCreates() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand() // Need content view to be active
        panel.updateBadge(count: 5)
        // Badge should exist in content view layer
        let badgeLayers = panel.contentView?.layer?.sublayers?.filter {
            $0 is CATextLayer
        }
        #expect(badgeLayers?.isEmpty == false)
    }

    @Test("updateBadge with zero hides badge")
    func updateBadgeZeroHides() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand()
        panel.updateBadge(count: 3)
        panel.updateBadge(count: 0)
        let badgeLayers = panel.contentView?.layer?.sublayers?.filter {
            $0 is CATextLayer
        }
        #expect(badgeLayers?.isEmpty ?? true)
    }

    @Test("hideBadge removes badge layer")
    func hideBadgeRemoves() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand()
        panel.updateBadge(count: 2)
        panel.hideBadge()
        let badgeLayers = panel.contentView?.layer?.sublayers?.filter {
            $0 is CATextLayer
        }
        #expect(badgeLayers?.isEmpty ?? true)
    }

    // MARK: - FileShelfView integration

    @Test("Panel has fileShelfView as subview")
    func panelHasFileShelfView() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        let shelfViews = panel.contentView?.subviews.compactMap { $0 as? FileShelfView }
        #expect(shelfViews?.count == 1)
    }

    // MARK: - Geometry update

    @Test("Geometry update repositions expanded panel")
    func geometryUpdateRepositions() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand()

        let frameBefore = panel.frame
        panel.geometry = makeTestGeometry(hasNotch: false)
        let frameAfter = panel.frame

        #expect(frameBefore.origin != frameAfter.origin)
    }

    @Test("Geometry update repositions shelfExpanded panel")
    func geometryUpdateRepositionsShelf() {
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expandShelf()

        let frameBefore = panel.frame
        panel.geometry = makeTestGeometry(hasNotch: false)
        let frameAfter = panel.frame

        #expect(frameBefore.origin != frameAfter.origin)
    }
}
