import Testing
import Foundation
@testable import DropZoneLib

struct AirDropServiceTests {
    @Test @MainActor
    func canShareIsFalseForEmpty() {
        #expect(AirDropService.canShare(urls: []) == false)
    }

    @Test @MainActor
    func shareEmptyDoesNotCrash() {
        AirDropService.share(urls: [])
    }
}
