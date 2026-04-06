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
        // Panel should be at popUpMenu level — high enough to float above most windows
        // but low enough for drag-and-drop to work
        #expect(panel.level == .popUpMenu)
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

    @Test("shelfExpanded panel has correct target size constant")
    func shelfExpandedSize() {
        // Verify the static size constant is correct
        let expectedSize = DropZonePanel.shelfExpandedSize
        #expect(expectedSize.width == 420)
        #expect(expectedSize.height == 100)

        // expandShelf() starts with an inset frame and animates to targetFrame;
        // animations don't complete synchronously, so verify the panel entered
        // the correct state rather than checking the mid-animation frame.
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expandShelf()
        #expect(panel.panelState == .shelfExpanded)
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

    // MARK: - External display positioning (Bug 1)

    @Test("Panel on external display (offset screen) positions correctly")
    func panelOnExternalDisplay() {
        let externalScreenFrame = NSRect(x: 1600, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(x: 2750, y: 1348, width: 260, height: 102),
            screenFrame: externalScreenFrame,
            hasNotch: false
        )

        let panel = DropZonePanel(geometry: geometry)
        panel.expand()

        // Panel should be positioned on the external display (x >= 1600)
        #expect(panel.frame.origin.x >= 1600, "Panel must be on external display")
        // Panel should be near top of external screen
        #expect(panel.frame.maxY <= 1440 + 1, "Panel must not exceed external screen top")
    }

    @Test("Panel on external display with notch positions at notch")
    func panelOnExternalDisplayWithNotch() {
        // Simulates a second MacBook display (e.g., Sidecar or external notched display)
        let externalScreenFrame = NSRect(x: 1600, y: 0, width: 1600, height: 1422)
        let notchRect = NSRect(x: 2300, y: 1390, width: 200, height: 32)
        let geometry = NotchGeometry(
            notchRect: notchRect,
            activationZone: NSRect(x: 2280, y: 1350, width: 240, height: 72),
            screenFrame: externalScreenFrame,
            hasNotch: true
        )

        let panel = DropZonePanel(geometry: geometry)
        panel.expand()

        // Panel should be on the external display
        #expect(panel.frame.origin.x >= 1600)
        // Panel should be centered around notch midX (2400)
        let panelMidX = panel.frame.midX
        #expect(abs(panelMidX - 2400) < 1)
    }

    @Test("Geometry update to external display repositions panel")
    func geometryUpdateToExternalDisplay() {
        // Start on built-in display
        let panel = DropZonePanel(geometry: makeTestGeometry(hasNotch: true))
        panel.expand()
        let builtInOrigin = panel.frame.origin

        // Switch to external display
        let externalGeometry = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(x: 2750, y: 1348, width: 260, height: 102),
            screenFrame: NSRect(x: 1600, y: 0, width: 2560, height: 1440),
            hasNotch: false
        )
        panel.geometry = externalGeometry
        let externalOrigin = panel.frame.origin

        // Panel should have moved to external display coordinates
        #expect(externalOrigin.x > builtInOrigin.x)
        #expect(externalOrigin.x >= 1600)
    }

    @Test("Multiple panels can coexist for different screens")
    func multiplePanelsCoexist() {
        let builtInGeometry = makeTestGeometry(hasNotch: true)
        let externalGeometry = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(x: 2750, y: 1348, width: 260, height: 102),
            screenFrame: NSRect(x: 1600, y: 0, width: 2560, height: 1440),
            hasNotch: false
        )

        let panel1 = DropZonePanel(geometry: builtInGeometry)
        let panel2 = DropZonePanel(geometry: externalGeometry)

        panel1.expand()
        panel2.expand()

        // Panels should be at different positions
        #expect(panel1.frame.origin.x != panel2.frame.origin.x)
        // Both should be in expanded state
        #expect(panel1.panelState == .expanded)
        #expect(panel2.panelState == .expanded)
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
