import Testing
import AppKit
@testable import DropZoneLib

@Suite("NotchGeometry Tests")
struct NotchGeometryTests {

    // MARK: - Test init with explicit values (no NSScreen needed)

    @Test("Geometry with notch has correct properties")
    func notchGeometryWithNotch() {
        let notchRect = NSRect(x: 700, y: 1390, width: 200, height: 32)
        let screenFrame = NSRect(x: 0, y: 0, width: 1600, height: 1422)
        let geometry = NotchGeometry(
            notchRect: notchRect,
            activationZone: NSRect(x: 680, y: 1350, width: 240, height: 72),
            screenFrame: screenFrame,
            hasNotch: true
        )

        #expect(geometry.hasNotch == true)
        #expect(geometry.notchRect != nil)
        #expect(geometry.notchRect == notchRect)
        #expect(geometry.screenFrame == screenFrame)
    }

    @Test("Geometry without notch has nil notchRect")
    func notchGeometryWithoutNotch() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(x: 0, y: 0, width: 100, height: 100),
            screenFrame: screenFrame,
            hasNotch: false
        )

        #expect(geometry.hasNotch == false)
        #expect(geometry.notchRect == nil)
    }

    // MARK: - Panel origin

    @Test("Panel origin centers on notch midX, grows downward from notch bottom")
    func panelOriginWithNotch() {
        let notchRect = NSRect(x: 700, y: 1390, width: 200, height: 32)
        let geometry = NotchGeometry(
            notchRect: notchRect,
            activationZone: .zero,
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )

        let size = NSSize(width: 320, height: 80)
        let origin = geometry.panelOrigin(for: size)

        // Centered on notch midX (800), growing downward from notch bottom (1390)
        #expect(abs(origin.x - 640) < 0.01)  // 800 - 160
        #expect(abs(origin.y - 1310) < 0.01) // 1390 - 80
    }

    @Test("Panel origin centers on screen without notch")
    func panelOriginWithoutNotch() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: .zero,
            screenFrame: screenFrame,
            hasNotch: false
        )

        let size = NSSize(width: 320, height: 80)
        let origin = geometry.panelOrigin(for: size)

        // Centered on screen (960), flush with top (1080)
        #expect(abs(origin.x - 800) < 0.01)  // 960 - 160
        #expect(abs(origin.y - 1000) < 0.01) // 1080 - 80
    }

    // MARK: - Activation zone / containsPoint

    @Test("containsPoint returns true for points inside activation zone")
    func containsPointInside() {
        let zone = NSRect(x: 680, y: 1350, width: 240, height: 72)
        let geometry = NotchGeometry(
            notchRect: NSRect(x: 700, y: 1390, width: 200, height: 32),
            activationZone: zone,
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )

        // Center of zone
        #expect(geometry.containsPoint(NSPoint(x: 800, y: 1386)))
        // Inside but near edge
        #expect(geometry.containsPoint(NSPoint(x: 681, y: 1351)))
    }

    @Test("containsPoint returns false for points outside activation zone")
    func containsPointOutside() {
        let zone = NSRect(x: 680, y: 1350, width: 240, height: 72)
        let geometry = NotchGeometry(
            notchRect: NSRect(x: 700, y: 1390, width: 200, height: 32),
            activationZone: zone,
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )

        // Below the zone
        #expect(!geometry.containsPoint(NSPoint(x: 800, y: 1349)))
        // Left of zone
        #expect(!geometry.containsPoint(NSPoint(x: 679, y: 1386)))
    }

    // MARK: - Design constants

    @Test("Design constants match expected values")
    func designConstants() {
        #expect(NotchGeometry.activationPaddingBottom == 40)
        #expect(NotchGeometry.activationPaddingSide == 20)
        #expect(NotchGeometry.expandedSize.width == 320)
        #expect(NotchGeometry.expandedSize.height == 80)
        #expect(NotchGeometry.cornerRadius == 18)
        #expect(NotchGeometry.fallbackPillSize.width == 200)
        #expect(NotchGeometry.fallbackPillSize.height == 32)
    }

    // MARK: - NSScreen-based init (uses real screen)

    @MainActor
    @Test("Init from main screen produces valid geometry")
    func initFromMainScreen() throws {
        let screen = try #require(NSScreen.main, "No main screen available")
        let geometry = NotchGeometry(screen: screen)
        #expect(geometry.screenFrame == screen.frame)
        #expect(geometry.activationZone.width > 0)
        #expect(geometry.activationZone.height > 0)
    }
}
