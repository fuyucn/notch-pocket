import Testing
@testable import DropZoneLib

struct PermissionsManagerTests {
    @Test @MainActor
    func inputMonitoringStatusReturnsAKnownCase() {
        let mgr = PermissionsManager()
        let status = mgr.inputMonitoringStatus
        // Any of the 3 cases is fine — we just confirm the API doesn't throw
        // and returns a well-known case in whatever environment this runs in.
        #expect(status == .granted || status == .denied || status == .undetermined)
    }

    @Test @MainActor
    func permissionStatusCasesAreDistinct() {
        #expect(PermissionStatus.granted != .denied)
        #expect(PermissionStatus.denied != .undetermined)
        #expect(PermissionStatus.granted != .undetermined)
    }
}
