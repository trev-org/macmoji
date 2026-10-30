#if os(macOS)
import AppKit
import Carbon.HIToolbox

struct ClipboardHotKey {
    static let command = 1 << 0
    static let shift = 1 << 1
    static let option = 1 << 2
    static let control = 1 << 3
    static let defaultModifiers = command | shift
    static let availableKeys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

    let key: String
    let modifiers: Int

    var keyCode: UInt32? {
        Self.keyCodes[key.uppercased()]
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers & Self.command != 0 { result |= UInt32(cmdKey) }
        if modifiers & Self.shift != 0 { result |= UInt32(shiftKey) }
        if modifiers & Self.option != 0 { result |= UInt32(optionKey) }
        if modifiers & Self.control != 0 { result |= UInt32(controlKey) }
        return result
    }

    var displayString: String {
        var value = ""
        if modifiers & Self.control != 0 { value += "⌃" }
        if modifiers & Self.option != 0 { value += "⌥" }
        if modifiers & Self.shift != 0 { value += "⇧" }
        if modifiers & Self.command != 0 { value += "⌘" }
        return value + key.uppercased()
    }

    private static let keyCodes: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
    ]
}

@MainActor
final class GlobalHotKey {
    private static weak var active: GlobalHotKey?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    init() {
        Self.active = self
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.id == 1 else { return status }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Self.active?.action?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(_ configuration: ClipboardHotKey, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        guard configuration.modifiers != 0, let keyCode = configuration.keyCode else { return false }
        self.action = action
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x4D4D4348, id: 1) // "MMCH"
        let status = RegisterEventHotKey(
            keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        hotKey = status == noErr ? reference : nil
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        action = nil
    }
}
#endif
