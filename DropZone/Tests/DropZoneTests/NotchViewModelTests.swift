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
    func draggingIntoHoverRectTransitionsToPopping() {
        let vm = makeVM()
        // hoverTriggerRect = screen.width*0.5 centered, 200 tall, maxY == notch.minY (968).
        // So rect is (400..1200, 768..968). Point (800, 900) is inside.
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        #expect(vm.status == .popping)
    }

    @Test @MainActor
    func draggingIntoActivationZoneTransitionsToOpened() {
        let vm = makeVM()
        // activationZone = (670..930, 908..1010). Point (800, 950) is inside.
        vm.updateMouseLocation(NSPoint(x: 800, y: 950), isDragging: true)
        #expect(vm.status == .opened)
    }

    @Test @MainActor
    func leavingAllRectsWhileDraggingReturnsToClosed() {
        let vm = makeVM()
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        #expect(vm.status == .popping)
        vm.updateMouseLocation(NSPoint(x: 100, y: 100), isDragging: true)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func dragEndedClosesIfNotInsideOpenedRect() {
        let vm = makeVM()
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: true)
        vm.updateMouseLocation(NSPoint(x: 800, y: 900), isDragging: false)
        #expect(vm.status == .closed)
    }

    @Test @MainActor
    func forceCloseResetsStatus() {
        let vm = makeVM()
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
