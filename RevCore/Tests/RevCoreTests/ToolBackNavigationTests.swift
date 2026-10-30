import Testing
@testable import RevCore

@Suite struct ToolBackNavigationTests {
    @Test func emptyQueryOrNoTextFieldReturnsToLauncher() {
        XCTAssertTrue(ToolBackNavigationPolicy.shouldReturnToLauncher(
            hasLauncherDestination: true,
            query: "",
            isPlainBackspace: true
        ))
        XCTAssertTrue(ToolBackNavigationPolicy.shouldReturnToLauncher(
            hasLauncherDestination: true,
            query: nil,
            isPlainBackspace: true
        ))
    }

    @Test func nonemptyQueryKeepsBackspaceInTextField() {
        XCTAssertFalse(ToolBackNavigationPolicy.shouldReturnToLauncher(
            hasLauncherDestination: true,
            query: "emoji",
            isPlainBackspace: true
        ))
        XCTAssertFalse(ToolBackNavigationPolicy.shouldReturnToLauncher(
            hasLauncherDestination: true,
            query: " ",
            isPlainBackspace: true
        ))
    }

    @Test func directOpenAndModifiedOrDifferentKeysDoNotNavigateBack() {
        XCTAssertFalse(ToolBackNavigationPolicy.shouldReturnToLauncher(
            hasLauncherDestination: false,
            query: "",
            isPlainBackspace: true
        ))
        XCTAssertFalse(ToolBackNavigationPolicy.shouldReturnToLauncher(
            hasLauncherDestination: true,
            query: "",
            isPlainBackspace: false
        ))
    }
}
