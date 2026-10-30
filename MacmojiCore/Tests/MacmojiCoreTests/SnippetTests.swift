import Foundation
import Testing
@testable import MacmojiCore

@Suite struct SnippetTests {
    @Test func keywordBufferMatchesExactSuffixAndHonorsWordBoundary() {
        let snippet = Snippet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Signature",
            text: "Regards",
            keyword: ";sig"
        )
        var buffer = SnippetKeywordBuffer()

        XCTAssertEqual(type("x;sig", into: &buffer, snippets: [snippet], boundary: true), nil)
        buffer.reset()
        XCTAssertEqual(
            type(" ;sig", into: &buffer, snippets: [snippet], boundary: true),
            SnippetKeywordMatch(snippetID: snippet.id, keyword: ";sig")
        )
        XCTAssertEqual(
            type(";sig", into: &buffer, snippets: [snippet], boundary: true),
            SnippetKeywordMatch(snippetID: snippet.id, keyword: ";sig")
        )
        XCTAssertEqual(
            type("x;sig", into: &buffer, snippets: [snippet], boundary: false),
            SnippetKeywordMatch(snippetID: snippet.id, keyword: ";sig")
        )
    }

    @Test func keywordBufferHandlesBackspaceAndDoesNotSubstringMatch() {
        let snippet = Snippet(name: "Email", text: "hello@example.com", keyword: "!email")
        var buffer = SnippetKeywordBuffer()
        XCTAssertEqual(type("!emai", into: &buffer, snippets: [snippet], boundary: true), nil)
        buffer.backspace()
        XCTAssertEqual(type("ail", into: &buffer, snippets: [snippet], boundary: true), nil)
        buffer.reset()
        XCTAssertEqual(
            type("!email", into: &buffer, snippets: [snippet], boundary: true)?.snippetID,
            snippet.id
        )
    }

    @Test func expandsPlaceholdersAndReportsCursorOffset() {
        let date = Date(timeIntervalSince1970: 1_704_164_645) // 2024-01-02 03:04:05 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let context = SnippetExpansionContext(
            clipboard: "copied",
            date: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let expansion = SnippetExpansionEngine.expand(
            "{day} {date} {time} {datetime} {clipboard}{cursor}!",
            context: context
        )

        XCTAssertEqual(
            expansion.text,
            "Tuesday 2024-01-02 03:04 2024-01-02 03:04 copied!"
        )
        XCTAssertEqual(expansion.cursorOffset, 1)
    }

    @Test func expandsCustomDateFormatAndOffsetAndPreservesUnknownPlaceholders() {
        let date = Date(timeIntervalSince1970: 1_704_164_645)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let context = SnippetExpansionContext(
            date: date,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        let expansion = SnippetExpansionEngine.expand(
            #"{date format="MMM d, yyyy" offset="+2d"} {unknown}"#,
            context: context
        )

        XCTAssertEqual(expansion.text, "Jan 4, 2024 {unknown}")
        XCTAssertEqual(expansion.cursorOffset, 0)
    }

    @Test func persistenceRoundTripKeepsMetadataAndVersion() throws {
        let storage = MemorySnippetStorage()
        let clock = SnippetTestClock()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let first = SnippetStore(storage: storage, now: { clock.now }, makeID: { id })
        let created = try first.create(name: "Greeting", text: "Hello\nthere", keyword: ";hi")
        clock.advance(by: 60)
        _ = first.recordUse(id: created.id)
        first.flush()

        let object = try JSONSerialization.jsonObject(with: storage.data ?? Data()) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 1)

        let reloaded = SnippetStore(storage: storage, now: { clock.now })
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.snippet(id: id)?.name, "Greeting")
        XCTAssertEqual(reloaded.snippet(id: id)?.text, "Hello\nthere")
        XCTAssertEqual(reloaded.snippet(id: id)?.keyword, ";hi")
        XCTAssertEqual(reloaded.snippet(id: id)?.useCount, 1)
        XCTAssertEqual(reloaded.snippet(id: id)?.lastUsedAt, clock.now)
    }

    @Test func importsRaycastArrayAndSkipsDuplicateKeywords() throws {
        let store = SnippetStore()
        let data = Data(
            """
            [
              {"name":"Signature","text":"Regards,\\nTrevor","keyword":";sig"},
              {"name":"Address","text":"One Main Street"},
              {"name":"Duplicate","text":"Other","keyword":";sig"}
            ]
            """.utf8
        )

        let summary = try store.importData(data)

        XCTAssertEqual(summary, SnippetImportSummary(importedCount: 2, skippedCount: 1))
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.allSnippets().first { $0.name == "Address" }?.keyword, nil)
    }

    @Test func searchUsesNameKeywordTextAndFrecency() throws {
        let clock = SnippetTestClock()
        let ids = SnippetIDSequence()
        let store = SnippetStore(now: { clock.now }, makeID: { ids.next() })
        let exact = try store.create(name: "Email", text: "plain", keyword: nil)
        let used = try store.create(name: "Contact", text: "email@example.com", keyword: "!mail")
        _ = store.recordUse(id: used.id)

        XCTAssertEqual(store.search("email").map(\.id), [used.id, exact.id])
        XCTAssertEqual(store.search("!mail").map(\.id), [used.id])
        XCTAssertEqual(store.search("example").map(\.id), [used.id])
    }

    private func type(
        _ value: String,
        into buffer: inout SnippetKeywordBuffer,
        snippets: [Snippet],
        boundary: Bool
    ) -> SnippetKeywordMatch? {
        var result: SnippetKeywordMatch?
        for character in value {
            if let match = buffer.type(
                character,
                snippets: snippets,
                requiresWordBoundary: boundary
            ) {
                result = match
            }
        }
        return result
    }
}

private final class SnippetTestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private final class SnippetIDSequence: @unchecked Sendable {
    private var value = 0

    func next() -> UUID {
        value += 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class MemorySnippetStorage: SnippetStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?

    var data: Data? {
        lock.lock(); defer { lock.unlock() }
        return storedData
    }

    func load() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storedData
    }

    func save(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        storedData = data
    }
}
