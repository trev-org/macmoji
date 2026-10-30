import Foundation
import Testing
@testable import RevCore

@Suite struct EmojiSearchTests {
    static let bundled = try! EmojiStore.bundled()

    @Test func testBundledDataIntegrity() throws {
        let store = Self.bundled
        XCTAssertTrue(store.source.hasPrefix("emojibase-data 18"), store.source)
        XCTAssertGreaterThan(store.emoji.count, 1800)
        var seen = Set<String>()
        for e in store.emoji {
            XCTAssertFalse(e.names.isEmpty, "\(e.emoji) has no names")
            XCTAssertFalse(e.emoji.isEmpty)
            XCTAssertTrue(seen.insert(e.emoji).inserted, "duplicate \(e.emoji)")
            if let s = e.skins { XCTAssertEqual(s.count, 5) }
            for n in e.names {
                XCTAssertTrue(n.allSatisfy(ShortcodeRules.isShortcodeChar), "bad shortcode '\(n)'")
            }
        }
    }

    @Test func testSlackNamesAndGitHubAliases() {
        let store = Self.bundled
        XCTAssertEqual(store.emoji(named: "+1")?.emoji, "👍")
        XCTAssertEqual(store.emoji(named: "thumbsup")?.emoji, "👍")
        XCTAssertEqual(store.emoji(named: "fire")?.emoji, "🔥")
        XCTAssertEqual(store.emoji(named: "joy")?.emoji, "😂")
        XCTAssertEqual(store.emoji(named: "tada")?.emoji, "🎉")
    }

    @Test func testSkinTone() {
        let thumbs = Self.bundled.emoji(named: "+1")!
        XCTAssertEqual(thumbs.rendered(tone: .none), "👍")
        XCTAssertEqual(thumbs.rendered(tone: .medium), "👍🏽")
        XCTAssertEqual(Self.bundled.emoji(named: "fire")!.rendered(tone: .dark), "🔥")
    }

    private let small = EmojiStore(emoji: [
        Emoji(emoji: "A", names: ["thumbsup", "+1"], keywords: ["like"], order: 1),
        Emoji(emoji: "B", names: ["thumbsdown"], order: 2),
        Emoji(emoji: "C", names: ["thu"], order: 3),
        Emoji(emoji: "D", names: ["math_thunder"], order: 4),
        Emoji(emoji: "E", names: ["tahiti_u"], order: 5),
        Emoji(emoji: "F", names: ["heart"], keywords: ["thumbprint"], order: 6),
    ])

    @Test func testNoHistoryUsesMatchTierOrder() {
        let r = EmojiSearch(store: small).search("thu", limit: 10)
        XCTAssertEqual(r.map(\.emoji.emoji), ["C", "A", "B", "D", "E", "F"])
        XCTAssertEqual(r.map(\.tier), [.exact, .prefix, .prefix, .substring, .fuzzy, .keyword])
    }

    @Test func testUsedEyesOutrankUnusedExactEye() {
        let eyeStore = EmojiStore(emoji: [
            Emoji(emoji: "👁", names: ["eye"], order: 1),
            Emoji(emoji: "👀", names: ["eyes"], order: 2),
        ])
        let clock = Clock()
        let usage = UsageStore(fileURL: nil, now: { clock.now })
        usage.record("👀")

        let r = EmojiSearch(store: eyeStore, usage: usage).search("eye", limit: 10)

        XCTAssertEqual(r.map(\.emoji.emoji), ["👀", "👁"])
        XCTAssertEqual(r.map(\.tier), [.prefix, .exact])
    }

    @Test func testUsedFuzzyAndKeywordMatchesOutrankUnusedExact() {
        let clock = Clock()
        let usage = UsageStore(fileURL: nil, now: { clock.now })
        usage.record("E")
        usage.record("F")

        let r = EmojiSearch(store: small, usage: usage).search("thu", limit: 10)

        // Equal frecency falls back to fuzzy before keyword; both used matches precede exact C.
        XCTAssertEqual(r.map(\.emoji.emoji), ["E", "F", "C", "A", "B", "D"])
    }

    @Test func testHigherFrecencyWinsAmongUsedMatches() {
        let clock = Clock()
        let usage = UsageStore(fileURL: nil, now: { clock.now })
        usage.record("E")
        usage.record("F")
        usage.record("F")

        let r = EmojiSearch(store: small, usage: usage).search("thu", limit: 10)

        // Higher-frecency keyword F outranks lower-frecency fuzzy E.
        XCTAssertEqual(Array(r.prefix(2).map(\.emoji.emoji)), ["F", "E"])
    }

    @Test func testEmptyQueryReturnsHistoryOnly() {
        let clock = Clock()
        let usage = UsageStore(fileURL: nil, now: { clock.now })
        usage.record("A")
        usage.record("B"); usage.record("B")

        let r = EmojiSearch(store: small, usage: usage).search("", limit: 10)

        XCTAssertEqual(r.map(\.emoji.emoji), ["B", "A"])
        XCTAssertEqual(r.map(\.tier), [.history, .history])
    }

    @Test func testFrecencyDecay() {
        let clock = Clock()
        let usage = UsageStore(fileURL: nil, now: { clock.now })
        usage.record("A")
        XCTAssertEqual(usage.score("A"), 1, accuracy: 1e-9)
        clock.now = clock.now.addingTimeInterval(usage.halfLife)
        XCTAssertEqual(usage.score("A"), 0.5, accuracy: 1e-9)
        XCTAssertEqual(usage.score("Z"), 0)
    }

    @Test func testUsagePersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("usage.json")
        let original = UsageStore(fileURL: url)
        original.record("🔥")
        original.flush()
        XCTAssertEqual(UsageStore(fileURL: url).record(for: "🔥")?.count, 1)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func testRealDataRanking() {
        let s = EmojiSearch(store: Self.bundled)
        XCTAssertEqual(s.search("fire").first?.emoji.emoji, "🔥")
        XCTAssertEqual(s.search("+1").first?.emoji.emoji, "👍")
        XCTAssertTrue(s.search("thu").contains { $0.emoji.emoji == "👍" })
        XCTAssertEqual(s.search("FIRE").first?.emoji.emoji, "🔥")
        XCTAssertTrue(s.search("").isEmpty)
        XCTAssertLessThanOrEqual(s.search("a").count, 8)
    }

    @Test func testSubsequence() {
        XCTAssertTrue(EmojiSearch.isSubsequence("tu", of: "thumbsup"))
        XCTAssertFalse(EmojiSearch.isSubsequence("ut", of: "tu"))
    }
}

final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_700_000_000) }
