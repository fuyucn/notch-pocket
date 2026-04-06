import Testing
import AppKit
@testable import DropZoneLib

@Suite("KeyboardShortcutManager Tests")
@MainActor
struct KeyboardShortcutManagerTests {

    @Test("Manager can be created")
    func creation() {
        let manager = KeyboardShortcutManager()
        #expect(manager.onToggleShelf == nil)
    }

    @Test("Register and unregister lifecycle is safe")
    func registerUnregister() {
        let manager = KeyboardShortcutManager()
        manager.register()
        manager.unregister()
    }

    @Test("Double unregister is safe")
    func doubleUnregister() {
        let manager = KeyboardShortcutManager()
        manager.register()
        manager.unregister()
        manager.unregister() // Should not crash
    }

    @Test("Unregister without register is safe")
    func unregisterWithoutRegister() {
        let manager = KeyboardShortcutManager()
        manager.unregister() // Should not crash
    }

    @Test("onToggleShelf callback can be set")
    func callbackSettable() {
        let manager = KeyboardShortcutManager()
        nonisolated(unsafe) var toggled = false
        manager.onToggleShelf = { toggled = true }
        #expect(!toggled)
    }

    @Test("Register sets current static instance")
    func registerSetsCurrent() {
        let manager = KeyboardShortcutManager()
        manager.register()
        #expect(KeyboardShortcutManager.current === manager)
        manager.unregister()
        #expect(KeyboardShortcutManager.current == nil)
    }

    @Test("Re-register replaces current instance")
    func reRegisterReplaces() {
        let manager1 = KeyboardShortcutManager()
        let manager2 = KeyboardShortcutManager()
        manager1.register()
        #expect(KeyboardShortcutManager.current === manager1)
        manager2.register()
        #expect(KeyboardShortcutManager.current === manager2)
        manager1.unregister()
        manager2.unregister()
    }
}
