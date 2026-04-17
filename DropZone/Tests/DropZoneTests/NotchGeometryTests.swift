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

    @Test("Panel origin centers on notch midX, top aligns with notch top edge")
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

        // Centered on notch midX (800), top aligns with notch top (1422 = 1390 + 32)
        #expect(abs(origin.x - 640) < 0.01)  // 800 - 160
        #expect(abs(origin.y - 1342) < 0.01) // 1422 - 80
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
        #expect(NotchGeometry.activationPaddingBottom == 60)
        #expect(NotchGeometry.activationPaddingTop == 10)
        #expect(NotchGeometry.activationPaddingSide == 30)
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

    // MARK: - Edge cases

    @Test("containsPoint on exact boundary of activation zone")
    func containsPointOnBoundary() {
        let zone = NSRect(x: 680, y: 1350, width: 240, height: 72)
        let geometry = NotchGeometry(
            notchRect: NSRect(x: 700, y: 1390, width: 200, height: 32),
            activationZone: zone,
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )

        // NSRect.contains uses half-open ranges: includes origin, excludes origin+size
        #expect(geometry.containsPoint(NSPoint(x: 680, y: 1350)))   // origin corner — inside
        #expect(!geometry.containsPoint(NSPoint(x: 920, y: 1422)))  // maxX, maxY — outside
    }

    @Test("Panel origin with zero-size request")
    func panelOriginZeroSize() {
        let geometry = NotchGeometry(
            notchRect: NSRect(x: 700, y: 1390, width: 200, height: 32),
            activationZone: .zero,
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )
        let origin = geometry.panelOrigin(for: NSSize(width: 0, height: 0))
        // Should be at notch midX (800) and notch maxY (1422)
        #expect(abs(origin.x - 800) < 0.01)
        #expect(abs(origin.y - 1422) < 0.01)
    }

    @Test("Panel origin with very large size clamps to negative coordinates")
    func panelOriginLargeSize() {
        let geometry = NotchGeometry(
            notchRect: NSRect(x: 700, y: 1390, width: 200, height: 32),
            activationZone: .zero,
            screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1422),
            hasNotch: true
        )
        let origin = geometry.panelOrigin(for: NSSize(width: 5000, height: 5000))
        // x = 800 - 2500 = -1700, y = 1422 - 5000 = -3578
        #expect(origin.x < 0)
        #expect(origin.y < 0)
    }

    @Test("Geometry on secondary screen with offset origin")
    func geometryWithOffsetScreen() {
        let screenFrame = NSRect(x: 1920, y: 0, width: 1600, height: 1422)
        let notchRect = NSRect(x: 2620, y: 1390, width: 200, height: 32)
        let geometry = NotchGeometry(
            notchRect: notchRect,
            activationZone: NSRect(x: 2600, y: 1350, width: 240, height: 72),
            screenFrame: screenFrame,
            hasNotch: true
        )

        let origin = geometry.panelOrigin(for: NSSize(width: 320, height: 80))
        // Centered on notch midX = 2720, top at notch maxY = 1422
        #expect(abs(origin.x - 2560) < 0.01) // 2720 - 160
        #expect(abs(origin.y - 1342) < 0.01) // 1422 - 80
        #expect(origin.x > 1920) // Must be on the secondary screen
    }

    @Test("Activation zone for non-notch screen is centered")
    func noNotchActivationZoneCentered() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: NSRect(
                x: screenFrame.midX - NotchGeometry.fallbackPillSize.width / 2 - NotchGeometry.activationPaddingSide,
                y: screenFrame.maxY - NotchGeometry.fallbackPillSize.height - NotchGeometry.activationPaddingBottom,
                width: NotchGeometry.fallbackPillSize.width + NotchGeometry.activationPaddingSide * 2,
                height: NotchGeometry.fallbackPillSize.height + NotchGeometry.activationPaddingBottom + NotchGeometry.activationPaddingTop
            ),
            screenFrame: screenFrame,
            hasNotch: false
        )

        // Screen center is at 960, activation zone should be roughly symmetric
        let zoneMidX = geometry.activationZone.midX
        #expect(abs(zoneMidX - 960) < 0.01)
    }

    @Test("Sendable conformance allows cross-isolation use")
    func sendableConformance() {
        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: .zero,
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            hasNotch: false
        )
        // Verify Sendable by assigning to a nonisolated(unsafe) var (compile-time check)
        nonisolated(unsafe) let captured = geometry
        #expect(captured.hasNotch == false)
    }

    // MARK: - Pre-activation constants and rect

    @Test
    func preActivatedSizeIs380x60() {
        #expect(NotchGeometry.preActivatedSize == NSSize(width: 380, height: 60))
    }

    @Test
    func shelfExpandedSizeIs600x360() {
        #expect(NotchGeometry.shelfExpandedSize == NSSize(width: 600, height: 360))
    }

    @Test
    func preActivationRectIsActivationZoneOutsetByPreActivationOutset() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
        let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
        let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)

        let pre = geo.preActivationRect
        #expect(pre.minX == activation.minX - NotchGeometry.preActivationOutset)
        #expect(pre.minY == activation.minY - NotchGeometry.preActivationOutset)
        #expect(pre.width == activation.width + NotchGeometry.preActivationOutset * 2)
        #expect(pre.height == activation.height + NotchGeometry.preActivationOutset * 2)
    }

    @Test
    func panelOriginCentersPreActivatedBarUnderNotch() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = NSRect(x: 400, y: 768, width: 200, height: 32)
        let activation = NSRect(x: 370, y: 708, width: 260, height: 102)
        let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)

        let origin = geo.panelOrigin(for: NotchGeometry.preActivatedSize)
        #expect(origin.x == notch.midX - NotchGeometry.preActivatedSize.width / 2)
        #expect(origin.y == notch.maxY - NotchGeometry.preActivatedSize.height)
    }
}
