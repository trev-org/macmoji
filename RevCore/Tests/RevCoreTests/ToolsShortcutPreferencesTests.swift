import Testing
@testable import RevCore

@Suite struct ToolsShortcutPreferencesTests {
    @Test func freshAndLegacyDefaultsMigrateToOptionSpace() {
        XCTAssertEqual(
            ToolsShortcutPreferencesMigration.migrate(
                fromVersion: nil,
                storedMode: nil,
                storedChordModifiers: nil,
                storedHotKeyKey: nil,
                storedHotKeyModifiers: nil
            ),
            ToolsShortcutPreferencesMigration.currentDefault
        )
        XCTAssertEqual(
            ToolsShortcutPreferencesMigration.migrate(
                fromVersion: nil,
                storedMode: .modifierChord,
                storedChordModifiers: [.option, .command],
                storedHotKeyKey: "V",
                storedHotKeyModifiers: [.shift, .command]
            ),
            ToolsShortcutPreferencesMigration.currentDefault
        )
        XCTAssertEqual(ToolsShortcutPreferencesMigration.currentDefault.mode, .regularKey)
        XCTAssertEqual(ToolsShortcutPreferencesMigration.currentDefault.hotKeyKey, "SPACE")
        XCTAssertEqual(
            ToolsShortcutPreferencesMigration.currentDefault.hotKeyModifiers,
            [.option]
        )
    }

    @Test func customModifierChordKeepsLegacyFallbackValues() {
        let migrated = ToolsShortcutPreferencesMigration.migrate(
            fromVersion: nil,
            storedMode: nil,
            storedChordModifiers: [.control, .option],
            storedHotKeyKey: nil,
            storedHotKeyModifiers: nil
        )

        XCTAssertEqual(
            migrated,
            ToolsShortcutPreferences(
                mode: .modifierChord,
                chordModifiers: [.control, .option],
                hotKeyKey: "V",
                hotKeyModifiers: [.shift, .command]
            )
        )
    }

    @Test func customKeyShortcutAndDisabledModeArePreserved() {
        XCTAssertEqual(
            ToolsShortcutPreferencesMigration.migrate(
                fromVersion: nil,
                storedMode: .regularKey,
                storedChordModifiers: nil,
                storedHotKeyKey: "K",
                storedHotKeyModifiers: [.control, .option]
            ),
            ToolsShortcutPreferences(
                mode: .regularKey,
                chordModifiers: [.option, .command],
                hotKeyKey: "K",
                hotKeyModifiers: [.control, .option]
            )
        )
        XCTAssertEqual(
            ToolsShortcutPreferencesMigration.migrate(
                fromVersion: nil,
                storedMode: .disabled,
                storedChordModifiers: nil,
                storedHotKeyKey: nil,
                storedHotKeyModifiers: nil
            )?.mode,
            .disabled
        )
    }

    @Test func completedMigrationDoesNotRunAgain() {
        XCTAssertEqual(
            ToolsShortcutPreferencesMigration.migrate(
                fromVersion: ToolsShortcutPreferencesMigration.currentVersion,
                storedMode: .modifierChord,
                storedChordModifiers: [.option, .command],
                storedHotKeyKey: "V",
                storedHotKeyModifiers: [.shift, .command]
            ),
            nil
        )
    }
}
