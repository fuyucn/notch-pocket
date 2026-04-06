import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for DropZone.
///
/// Registers a global hotkey (Cmd+Shift+D by default) to toggle the shelf.
/// Uses Carbon's RegisterEventHotKey for true global shortcuts that work
/// even when the app is not focused.
@MainActor
public final class KeyboardShortcutManager {
    /// Called when the toggle-shelf shortcut is triggered.
    public var onToggleShelf: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// The shared instance pointer used by the Carbon callback.
    static var current: KeyboardShortcutManager?

    public init() {}

    /// Register the global hotkey (Cmd+Shift+D).
    public func register() {
        Self.current = self

        // Install a Carbon event handler for hotkey events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard handlerResult == noErr else { return }

        // Register Cmd+Shift+D
        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("DRZN"),
            id: 1
        )

        let keyCode: UInt32 = UInt32(kVK_ANSI_D)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    /// Unregister the global hotkey.
    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        Self.current = nil
    }

    /// Called from the Carbon callback on the main thread.
    fileprivate func handleHotKey() {
        onToggleShelf?()
    }
}

/// Convert a 4-character string to OSType.
private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) + OSType(char)
    }
    return result
}

/// Carbon event callback — must be a free function.
private func hotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    MainActor.assumeIsolated {
        KeyboardShortcutManager.current?.handleHotKey()
    }
    return noErr
}
