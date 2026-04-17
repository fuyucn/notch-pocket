import Testing
import AppKit
@testable import DropZoneLib

struct NotchViewModelTests {
    @MainActor
    private func makeVM() -> NotchViewModel {
        let notch = NSRect(x: 700, y: 968, width: 200, height: 32)
        let activation = NSRect(x: 670, y: 908, width: 260, height: 102)
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let geo = NotchGeometry(notchRect: notch, activationZone: activation, screenFrame: screen, hasNotch: true)
        return NotchViewModel(geometry: geo)
    }

    @Test @MainActor
    func initialStatusIsClosed() {
        let vm = makeVM()
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func notDraggingKeepsStatusClosed() {
        let vm = makeVM()
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: false)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func fileDraggingIntoHoverRectTransitionsToPopping() {
        let vm = makeVM()
        vm.isFileDragging = true
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        #expect(vm.status == .popping)
    }

    @Test @MainActor
    func fileDraggingIntoActivationZoneTransitionsToOpened() {
        let vm = makeVM()
        vm.isFileDragging = true
        vm.updateMouseLocation(NSPoint(x: 800, y: 950), isDragging: true)
        #expect(vm.status == .opened)
    }

    @Test @MainActor
    func leavingAllRectsWhileFileDraggingReturnsToClosed() {
        let vm = makeVM()
        vm.isFileDragging = true
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        #expect(vm.status == .popping)
        vm.updateMouseLocation(NSPoint(x: 100, y: 100), isDragging: true)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func windowDragIgnoredWhenNoFileDrag() {
        let vm = makeVM()
        // isFileDragging stays false (no real file drag). Moving the cursor
        // with mouse pressed (isDragging=true) must NOT pop the panel.
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func fileDragEndedClosesIfNotInsideOpenedRect() {
        let vm = makeVM()
        vm.isFileDragging = true
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        vm.isFileDragging = false
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: false)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func forceCloseResetsStatus() {
        let vm = makeVM()
        vm.isFileDragging = true
        vm.updateMouseLocation(NSPoint(x: 800, y: 950), isDragging: true)
        #expect(vm.status == .opened)
        vm.forceClose()
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func markDroppedKeepsStatusOpenedEvenWithoutDrag() {
        let vm = makeVM()
        vm.markDropped(stickyFor: 1.0)
        #expect(vm.status == .opened)
        // Simulate cursor moving far away without drag; status should stay .opened.
        vm.updateMouseLocation(NSPoint(x: -500, y: -500), isDragging: false)
        #expect(vm.status == .opened)
    }

    @Test @MainActor
    func markDroppedWithZeroStickinessImmediatelyExpires() {
        let vm = makeVM()
        vm.markDropped(stickyFor: 0)
        // We're .opened right after markDropped but the deadline has already passed.
        // Next updateMouseLocation should fall through to normal gating.
        vm.updateMouseLocation(NSPoint(x: -500, y: -500), isDragging: false)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func shelfManagerWeakReferenceCanBeSet() {
        let vm = makeVM()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let shelf = FileShelfManager(directory: tmp)
        vm.shelfManager = shelf
        #expect(vm.shelfManager === shelf)
    }

    @Test @MainActor
    func shelfRefreshTokenStartsAtZeroAndIncrements() {
        let vm = makeVM()
        #expect(vm.shelfRefreshToken == 0)
        vm.shelfRefreshToken &+= 1
        #expect(vm.shelfRefreshToken == 1)
    }
}
