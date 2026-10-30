#if os(macOS)
import AppKit
import Carbon.HIToolbox
import RevCore

private let toolsHotKeySignature: OSType = 0x5256544C // "RVTL"

private func toolsHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
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
    guard status == noErr else { return status }
    guard identifier.signature == toolsHotKeySignature, identifier.id == 1 else {
        return OSStatus(eventNotHandledErr)
    }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GlobalHotKey.invokeActiveHandler()
        }
    }
    return noErr
}

extension ToolsShortcutMode {
    var label: String {
        switch self {
        case .disabled: return "Off"
        case .modifierChord: return "Modifier chord"
        case .regularKey: return "Keyboard shortcut"
        }
    }
}

struct ModifierChordOption: Identifiable {
    let modifiers: Int
    let label: String
    var id: Int { modifiers }

    static let available: [ModifierChordOption] = [
        ModifierChordOption(
            modifiers: GlobalHotKeyConfiguration.option | GlobalHotKeyConfiguration.command,
            label: "⌥⌘"
        ),
        ModifierChordOption(
            modifiers: GlobalHotKeyConfiguration.control | GlobalHotKeyConfiguration.option,
            label: "⌃⌥"
        ),
        ModifierChordOption(
            modifiers: GlobalHotKeyConfiguration.shift | GlobalHotKeyConfiguration.command,
            label: "⇧⌘"
        ),
        ModifierChordOption(
            modifiers: GlobalHotKeyConfiguration.control | GlobalHotKeyConfiguration.command,
            label: "⌃⌘"
        ),
    ]
}

struct GlobalHotKeyConfiguration {
    static let command = Int(ShortcutModifiers.command.rawValue)
    static let option = Int(ShortcutModifiers.option.rawValue)
    static let control = Int(ShortcutModifiers.control.rawValue)
    static let shift = Int(ShortcutModifiers.shift.rawValue)
    static let availableKeys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["SPACE"]

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
        let normalizedKey = key.uppercased()
        let keyDisplay = normalizedKey == "SPACE" ? "Space" : normalizedKey
        return Self.modifierDisplay(modifiers) + keyDisplay
    }

    static func modifierDisplay(_ modifiers: Int) -> String {
        var value = ""
        if modifiers & control != 0 { value += "⌃" }
        if modifiers & option != 0 { value += "⌥" }
        if modifiers & shift != 0 { value += "⇧" }
        if modifiers & command != 0 { value += "⌘" }
        return value
    }

    static func key(for keyCode: UInt16) -> String? {
        keyCodes.first { $0.value == UInt32(keyCode) }?.key
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Int {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result = 0
        if flags.contains(.command) { result |= command }
        if flags.contains(.option) { result |= option }
        if flags.contains(.control) { result |= control }
        if flags.contains(.shift) { result |= shift }
        return result
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
        "SPACE": UInt32(kVK_Space),
    ]
}

@MainActor
final class GlobalHotKey {
    fileprivate static weak var active: GlobalHotKey?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handlerInstalled = false
    private var action: (@MainActor () -> Void)?

    init() {
        Self.active = self
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            toolsHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        handlerInstalled = status == noErr && eventHandler != nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(_ configuration: GlobalHotKeyConfiguration, action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        let safeModifiers = GlobalHotKeyConfiguration.command
            | GlobalHotKeyConfiguration.option
            | GlobalHotKeyConfiguration.control
        guard handlerInstalled,
              configuration.modifiers & safeModifiers != 0,
              let keyCode = configuration.keyCode else { return false }
        self.action = action
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: toolsHotKeySignature, id: 1)
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

    fileprivate static func invokeActiveHandler() {
        active?.action?()
    }
}
#endif
