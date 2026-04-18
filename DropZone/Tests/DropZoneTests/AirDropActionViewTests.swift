import Testing
import Foundation
@testable import DropZoneLib

struct AirDropActionViewTests {
    @Test @MainActor
    func disabledStateCapturedInView() {
        let v = AirDropActionView(isEnabled: false, onTap: {})
        #expect(v.isEnabled == false)
    }

    @Test @MainActor
    func onTapHandlerInvoked() {
        var called = 0
        let v = AirDropActionView(isEnabled: true, onTap: { called += 1 })
        v.onTap()
        #expect(called == 1)
    }

    @Test @MainActor
    func onFrameChangeForwardsRect() {
        var captured: CGRect = .zero
        let v = AirDropActionView(
            isEnabled: true,
            onTap: {},
            onFrameChange: { captured = $0 }
        )
        v.onFrameChange(CGRect(x: 10, y: 20, width: 86, height: 86))
        #expect(captured == CGRect(x: 10, y: 20, width: 86, height: 86))
    }

    @Test @MainActor
    func defaultSizeIsSquareAt86() {
        let v = AirDropActionView(isEnabled: true, onTap: {})
        #expect(v.size == 86)
    }
}
