import Testing
@testable import RevCore

@Suite struct ModifierChordTests {
    private let chord: ShortcutModifiers = [.option, .command]

    @Test func triggersOnShortExactChordRelease() {
        var machine = ModifierChordStateMachine(chord: chord)
        XCTAssertEqual(machine.flagsChanged(modifiers: [.option], at: 1.0), .none)
        XCTAssertEqual(machine.flagsChanged(modifiers: chord, at: 1.05), .none)
        XCTAssertEqual(machine.flagsChanged(modifiers: [.option], at: 1.10), .none)
        XCTAssertEqual(machine.flagsChanged(modifiers: [], at: 1.15), .trigger)
    }

    @Test func partialOrLongChordDoesNotTrigger() {
        var partial = ModifierChordStateMachine(chord: chord)
        partial.flagsChanged(modifiers: [.option], at: 1.0)
        XCTAssertEqual(partial.flagsChanged(modifiers: [], at: 1.1), .none)

        var held = ModifierChordStateMachine(chord: chord)
        held.flagsChanged(modifiers: chord, at: 2.0)
        XCTAssertEqual(held.flagsChanged(modifiers: [], at: 2.5), .none)
    }

    @Test func keyOrMouseInterruptionCancelsChord() {
        var keyInterrupted = ModifierChordStateMachine(chord: chord)
        keyInterrupted.flagsChanged(modifiers: chord, at: 1.0)
        keyInterrupted.interrupt()
        XCTAssertEqual(keyInterrupted.flagsChanged(modifiers: [], at: 1.1), .none)

        var mouseInterrupted = ModifierChordStateMachine(chord: chord)
        mouseInterrupted.flagsChanged(modifiers: chord, at: 2.0)
        mouseInterrupted.interrupt()
        XCTAssertEqual(mouseInterrupted.flagsChanged(modifiers: [], at: 2.1), .none)
    }

    @Test func extraModifierCancelsUntilAllModifiersAreReleased() {
        var machine = ModifierChordStateMachine(chord: chord)
        machine.flagsChanged(modifiers: chord, at: 1.0)
        machine.flagsChanged(modifiers: [.option, .command, .shift], at: 1.1)
        XCTAssertEqual(machine.flagsChanged(modifiers: chord, at: 1.2), .none)
        XCTAssertEqual(machine.flagsChanged(modifiers: [], at: 1.3), .none)

        machine.flagsChanged(modifiers: chord, at: 2.0)
        XCTAssertEqual(machine.flagsChanged(modifiers: [], at: 2.1), .trigger)
    }
}

@Suite struct ToolRegistryTests {
    private let emoji = RevTool(
        id: "emoji",
        name: "Emoji Picker",
        keywords: ["emoji", "smiley"],
        systemImageName: "face.smiling"
    )
    private let clipboard = RevTool(
        id: "clipboard",
        name: "Clipboard History",
        keywords: ["clipboard", "history", "paste"],
        systemImageName: "clipboard"
    )

    @Test func emptyQueryPreservesRegistrationOrder() {
        let registry = ToolRegistry(tools: [emoji, clipboard])
        XCTAssertEqual(registry.search("").map(\.id), ["emoji", "clipboard"])
    }

    @Test func filtersNamesKeywordsAndFuzzySubsequences() {
        let registry = ToolRegistry(tools: [emoji, clipboard])
        XCTAssertEqual(registry.search("emoji").map(\.id), ["emoji"])
        XCTAssertEqual(registry.search("paste").map(\.id), ["clipboard"])
        XCTAssertEqual(registry.search("cbh").map(\.id), ["clipboard"])
        XCTAssertTrue(registry.search("missing").isEmpty)
    }

    @Test func registeringExistingIDReplacesInPlace() {
        var registry = ToolRegistry(tools: [emoji, clipboard])
        registry.register(RevTool(
            id: "emoji",
            name: "Emoji Search",
            systemImageName: "face.smiling"
        ))
        XCTAssertEqual(registry.tools.map(\.name), ["Emoji Search", "Clipboard History"])
    }
}
