import AppKit
import Carbon.HIToolbox

// Carbon hot-key callbacks are bare C function pointers and can't capture Swift
// state, so registered actions are routed by id through this file-scoped table.
// Everything here runs on the main thread (Carbon delivers hot keys there).
private var hotkeyActions: [UInt32: () -> Void] = [:]
private var hotkeyHandlerInstalled = false
private var hotkeyNextID: UInt32 = 1

private func installHotkeyHandlerIfNeeded() {
    guard !hotkeyHandlerInstalled else { return }
    hotkeyHandlerInstalled = true

    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
        guard let event else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &hotKeyID)
        if status == noErr, let action = hotkeyActions[hotKeyID.id] {
            action()
        }
        return noErr
    }, 1, &spec, nil, nil)
}

/// A single global hot key registered with the system. Uses Carbon's
/// `RegisterEventHotKey` — the same mechanism most macOS apps use — which needs
/// **no** Accessibility permission and no event tap.
@MainActor
final class GlobalHotkey {
    private var ref: EventHotKeyRef?
    private let id: UInt32

    // OSType 'WISP'
    private static let signature: OSType = Array("WISP".utf8).reduce(0) { ($0 << 8) + OSType($1) }

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHotkeyHandlerIfNeeded()

        self.id = hotkeyNextID
        hotkeyNextID += 1
        hotkeyActions[id] = action

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: GlobalHotkey.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            hotkeyActions[id] = nil
            return nil
        }
        self.ref = ref
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        hotkeyActions[id] = nil
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        hotkeyActions[id] = nil
    }
}
