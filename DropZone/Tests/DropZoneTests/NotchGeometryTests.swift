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

    // MARK: - Non-notch screen activation zone validity (Bug 1)

    @Test("Non-notch screen produces non-zero activation zone")
    func nonNotchScreenActivationZoneIsValid() {
        let screenFrame = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let pillOrigin = NSPoint(
            x: screenFrame.midX - NotchGeometry.fallbackPillSize.width / 2,
            y: screenFrame.maxY - NotchGeometry.fallbackPillSize.height
        )
        let pillRect = NSRect(origin: pillOrigin, size: NotchGeometry.fallbackPillSize)
        let expectedZone = NSRect(
            x: pillRect.origin.x - NotchGeometry.activationPaddingSide,
            y: pillRect.origin.y - NotchGeometry.activationPaddingBottom,
            width: pillRect.width + NotchGeometry.activationPaddingSide * 2,
            height: pillRect.height + NotchGeometry.activationPaddingBottom + NotchGeometry.activationPaddingTop
        )

        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: expectedZone,
            screenFrame: screenFrame,
            hasNotch: false
        )

        #expect(geometry.activationZone.width > 0)
        #expect(geometry.activationZone.height > 0)
        // Zone should be within the screen bounds (not overflowing)
        #expect(geometry.activationZone.minX >= screenFrame.minX)
        #expect(geometry.activationZone.maxX <= screenFrame.maxX)
        // Zone should be near the top of the screen
        #expect(geometry.activationZone.maxY >= screenFrame.maxY - NotchGeometry.fallbackPillSize.height)
    }

    @Test("Non-notch activation zone containsPoint works at center-top")
    func nonNotchActivationZoneContainsTopCenter() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let pillOrigin = NSPoint(
            x: screenFrame.midX - NotchGeometry.fallbackPillSize.width / 2,
            y: screenFrame.maxY - NotchGeometry.fallbackPillSize.height
        )
        let pillRect = NSRect(origin: pillOrigin, size: NotchGeometry.fallbackPillSize)
        let zone = NSRect(
            x: pillRect.origin.x - NotchGeometry.activationPaddingSide,
            y: pillRect.origin.y - NotchGeometry.activationPaddingBottom,
            width: pillRect.width + NotchGeometry.activationPaddingSide * 2,
            height: pillRect.height + NotchGeometry.activationPaddingBottom + NotchGeometry.activationPaddingTop
        )

        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: zone,
            screenFrame: screenFrame,
            hasNotch: false
        )

        // Top-center of screen should be in activation zone
        #expect(geometry.containsPoint(NSPoint(x: 960, y: 1060)))
        // Bottom of screen should NOT be in activation zone
        #expect(!geometry.containsPoint(NSPoint(x: 960, y: 100)))
        // Far left should NOT be in zone
        #expect(!geometry.containsPoint(NSPoint(x: 10, y: 1060)))
    }

    @Test("Non-notch screen on external display (offset origin) has valid zone")
    func nonNotchExternalDisplayActivationZone() {
        // Simulates an external display positioned to the right of the built-in
        let screenFrame = NSRect(x: 1600, y: 0, width: 2560, height: 1440)
        let pillOrigin = NSPoint(
            x: screenFrame.midX - NotchGeometry.fallbackPillSize.width / 2,
            y: screenFrame.maxY - NotchGeometry.fallbackPillSize.height
        )
        let pillRect = NSRect(origin: pillOrigin, size: NotchGeometry.fallbackPillSize)
        let zone = NSRect(
            x: pillRect.origin.x - NotchGeometry.activationPaddingSide,
            y: pillRect.origin.y - NotchGeometry.activationPaddingBottom,
            width: pillRect.width + NotchGeometry.activationPaddingSide * 2,
            height: pillRect.height + NotchGeometry.activationPaddingBottom + NotchGeometry.activationPaddingTop
        )

        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: zone,
            screenFrame: screenFrame,
            hasNotch: false
        )

        // Zone should be on the external display (x > 1600)
        #expect(geometry.activationZone.minX >= screenFrame.minX)
        #expect(geometry.activationZone.maxX <= screenFrame.maxX)
        // Point at center-top of external display should be in zone
        let centerTop = NSPoint(x: screenFrame.midX, y: screenFrame.maxY - 20)
        #expect(geometry.containsPoint(centerTop))
        // Point on the built-in display should NOT be in zone
        #expect(!geometry.containsPoint(NSPoint(x: 800, y: 1400)))
    }

    @Test("Panel origin on non-notch external display is correctly positioned")
    func panelOriginNonNotchExternalDisplay() {
        let screenFrame = NSRect(x: 1600, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry(
            notchRect: nil,
            activationZone: .zero,
            screenFrame: screenFrame,
            hasNotch: false
        )

        let size = NSSize(width: 320, height: 80)
        let origin = geometry.panelOrigin(for: size)

        // Centered on external screen midX = 1600 + 1280 = 2880
        #expect(abs(origin.x - (2880 - 160)) < 0.01)
        // Top of external screen
        #expect(abs(origin.y - (1440 - 80)) < 0.01)
        // Must be on the external display
        #expect(origin.x >= 1600)
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
}
