import Testing
import Foundation
@testable import DropZoneLib

struct AirDropActionViewTests {
    @Test @MainActor
    func disabledStateCapturedInView() {
        let v = AirDropActionView(isEnabled: false, onTap: {}, onDropFiles: { _ in })
        #expect(v.isEnabled == false)
    }

    @Test @MainActor
    func onTapHandlerInvoked() {
        var called = 0
        let v = AirDropActionView(isEnabled: true, onTap: { called += 1 }, onDropFiles: { _ in })
        v.onTap()
        #expect(called == 1)
    }

    @Test @MainActor
    func onDropFilesHandlerInvoked() {
        var received: [URL] = []
        let v = AirDropActionView(
            isEnabled: true,
            onTap: {},
            onDropFiles: { urls in received = urls }
        )
        v.onDropFiles([URL(fileURLWithPath: "/tmp/foo.txt"), URL(fileURLWithPath: "/tmp/bar.pdf")])
        #expect(received.count == 2)
    }

    @Test @MainActor
    func defaultSizeIsSquareAt86() {
        let v = AirDropActionView(isEnabled: true, onTap: {}, onDropFiles: { _ in })
        #expect(v.size == 86)
    }
}
