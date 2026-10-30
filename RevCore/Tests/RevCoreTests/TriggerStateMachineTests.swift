import Foundation
import Testing
@testable import RevCore

@Suite struct TriggerStateMachineTests {
    private func run(_ text: String, exact: Set<String> = []) -> (TriggerStateMachine, [TriggerStateMachine.Action]) {
        var sm = TriggerStateMachine(isExactName: { exact.contains($0) })
        var actions: [TriggerStateMachine.Action] = []
        for c in text { actions.append(sm.handle(.character(c))) }
        return (sm, actions)
    }

    private func everShows(_ text: String) -> Bool {
        run(text).1.contains { if case .show = $0 { return true }; return false }
    }

    @Test func testThuOpensPicker() {
        let (sm, actions) = run(":thu")
        XCTAssertEqual(sm.state, .querying("thu"))
        XCTAssertEqual(actions, [.none, .none, .show(query: "th"), .show(query: "thu")])
        XCTAssertTrue(sm.isPickerVisible)
        XCTAssertEqual(sm.deleteCountForCommit, 4)
    }

    @Test func testOneCharDoesNotOpen() {
        let (sm, _) = run("hi :t")
        XCTAssertEqual(sm.state, .querying("t"))
        XCTAssertFalse(sm.isPickerVisible)
    }

    @Test func testTimeNeverTriggers() {
        XCTAssertFalse(everShows("time: 10:30"))
        XCTAssertFalse(everShows("at 10:30 ok"))
    }

    @Test func testURLsNeverTrigger() {
        XCTAssertFalse(everShows("https://example.com/a:bc"))
        XCTAssertFalse(everShows("see :/usr/bin"))
    }

    @Test func testColonInsideWordDoesNotArm() {
        XCTAssertFalse(everShows("a:bc"))
        XCTAssertFalse(everShows("key:value"))
    }

    @Test func testBoundaries() {
        XCTAssertTrue(everShows("(:smile"))
        XCTAssertTrue(everShows("[:smile"))
        XCTAssertTrue(everShows("hello\t:smile"))
        XCTAssertTrue(everShows("line\n:smile"))
    }

    @Test func testDigitRightAfterColonCancels() {
        XCTAssertFalse(everShows(" :100"))
        // Digits later in the query are fine.
        XCTAssertTrue(everShows(" :e100"))
    }

    @Test func testSpaceCancelsAndHides() {
        let (sm, actions) = run(":thu ")
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(actions.last, .hide)
    }

    @Test func testPlusOneAndDash() {
        XCTAssertFalse(everShows(":+")) // only 1 char
        let (sm, _) = run(":+1")
        XCTAssertEqual(sm.currentQuery, "+1")
        XCTAssertTrue(sm.isPickerVisible)
        XCTAssertEqual(run(":t-rex").0.currentQuery, "t-rex")
    }

    @Test func testAutoReplaceExactName() {
        let (sm, actions) = run(":fire:", exact: ["fire"])
        XCTAssertEqual(actions.last, .autoReplace(name: "fire", deleteCount: 6))
        XCTAssertEqual(sm.state, .idle)
    }

    @Test func testClosingColonWithoutMatchHides() {
        let (_, actions) = run(":zzqq:", exact: ["fire"])
        XCTAssertEqual(actions.last, .hide)
    }

    @Test func testBackspaceShrinksAndPastColon() {
        var (sm, _) = run(":thu")
        XCTAssertEqual(sm.handle(.backspace), .show(query: "th"))
        XCTAssertEqual(sm.handle(.backspace), .hide)
        XCTAssertEqual(sm.state, .querying("t"))
        XCTAssertEqual(sm.handle(.backspace), .none)
        XCTAssertEqual(sm.state, .armed)
        XCTAssertEqual(sm.handle(.backspace), .none) // deleted the ':'
        XCTAssertEqual(sm.state, .idle)
    }

    @Test func testResetHides() {
        var (sm, _) = run(":thu")
        XCTAssertEqual(sm.handle(.reset), .hide)
        XCTAssertEqual(sm.state, .idle)
        // After reset, context is unknown -> treated as boundary.
        sm.handle(.character(":"))
        XCTAssertEqual(sm.state, .armed)
    }

    @Test func testCommitThenColonDoesNotArm() {
        var (sm, _) = run(":thu")
        sm.didCommit()
        XCTAssertEqual(sm.state, .idle)
        sm.handle(.character(":"))
        XCTAssertEqual(sm.state, .idle)
    }

    @Test func testUppercaseCancels() {
        XCTAssertFalse(everShows(":Smile"))
        let (sm, actions) = run(":smI")
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(actions.last, .hide)
    }

    @Test func testDoubleColonDoesNotArm() {
        XCTAssertFalse(everShows("::smile"))
    }
}
