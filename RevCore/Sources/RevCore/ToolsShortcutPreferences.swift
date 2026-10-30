import Foundation

public enum ToolsShortcutMode: String, CaseIterable, Codable, Sendable {
    case disabled
    case modifierChord
    case regularKey
}

public struct ToolsShortcutPreferences: Equatable, Sendable {
    public var mode: ToolsShortcutMode
    public var chordModifiers: ShortcutModifiers
    public var hotKeyKey: String
    public var hotKeyModifiers: ShortcutModifiers

    public init(
        mode: ToolsShortcutMode,
        chordModifiers: ShortcutModifiers,
        hotKeyKey: String,
        hotKeyModifiers: ShortcutModifiers
    ) {
        self.mode = mode
        self.chordModifiers = chordModifiers
        self.hotKeyKey = hotKeyKey
        self.hotKeyModifiers = hotKeyModifiers
    }
}

/// One-time migration from the modifier-only Tools default to Option-Space.
///
/// Every field is materialized during migration. That preserves the old effective values when a
/// user changed only one setting and the remaining values still came from registered defaults.
public enum ToolsShortcutPreferencesMigration {
    public static let currentVersion = 1

    public static let legacyDefault = ToolsShortcutPreferences(
        mode: .modifierChord,
        chordModifiers: [.option, .command],
        hotKeyKey: "V",
        hotKeyModifiers: [.shift, .command]
    )

    public static let currentDefault = ToolsShortcutPreferences(
        mode: .regularKey,
        chordModifiers: [.option, .command],
        hotKeyKey: "SPACE",
        hotKeyModifiers: [.option]
    )

    /// Returns preferences to persist, or `nil` when this migration has already run.
    public static func migrate(
        fromVersion version: Int?,
        storedMode: ToolsShortcutMode?,
        storedChordModifiers: ShortcutModifiers?,
        storedHotKeyKey: String?,
        storedHotKeyModifiers: ShortcutModifiers?
    ) -> ToolsShortcutPreferences? {
        guard (version ?? 0) < currentVersion else { return nil }

        let effective = ToolsShortcutPreferences(
            mode: storedMode ?? legacyDefault.mode,
            chordModifiers: storedChordModifiers ?? legacyDefault.chordModifiers,
            hotKeyKey: storedHotKeyKey ?? legacyDefault.hotKeyKey,
            hotKeyModifiers: storedHotKeyModifiers ?? legacyDefault.hotKeyModifiers
        )

        guard effective.mode == legacyDefault.mode,
              effective.chordModifiers == legacyDefault.chordModifiers else {
            return effective
        }
        return currentDefault
    }
}
