import Testing
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
}
