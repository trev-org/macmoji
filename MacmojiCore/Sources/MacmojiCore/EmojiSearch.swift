import Foundation

/// Ranked shortcode search (plan decision 6):
/// exact name > prefix > substring > fuzzy subsequence > keyword, frecency boost within each tier.
public struct EmojiSearch: Sendable {
    public enum Tier: Int, Comparable, Sendable {
        case exact = 0, prefix, substring, fuzzy, keyword
        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Result: Equatable, Sendable {
        public let emoji: Emoji
        /// The name (or keyword) that matched.
        public let matchedName: String
        public let tier: Tier
    }

    public let store: EmojiStore
    public let usage: UsageStore?

    public init(store: EmojiStore, usage: UsageStore? = nil) {
        self.store = store
        self.usage = usage
    }

    public func search(_ rawQuery: String, limit: Int = 8) -> [Result] {
        let query = rawQuery.lowercased()
        guard !query.isEmpty else { return [] }
        var scored: [(Result, Double, Int)] = []
        for e in store.emoji {
            guard let (tier, name) = Self.match(query, e) else { continue }
            scored.append((Result(emoji: e, matchedName: name, tier: tier), usage?.score(e.emoji) ?? 0, name.count))
        }
        scored.sort { a, b in
            if a.0.tier != b.0.tier { return a.0.tier < b.0.tier }
            if a.1 != b.1 { return a.1 > b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
            return a.0.emoji.order < b.0.emoji.order
        }
        return scored.prefix(limit).map { $0.0 }
    }

    static func match(_ q: String, _ e: Emoji) -> (Tier, String)? {
        var best: (Tier, String)?
        func consider(_ t: Tier, _ n: String) {
            if best == nil || t < best!.0 || (t == best!.0 && n.count < best!.1.count) { best = (t, n) }
        }
        for n in e.names {
            if n == q { consider(.exact, n) }
            else if n.hasPrefix(q) { consider(.prefix, n) }
            else if n.contains(q) { consider(.substring, n) }
            else if q.count >= 2, isSubsequence(q, of: n) { consider(.fuzzy, n) }
        }
        if best == nil {
            for k in e.keywords where k.lowercased().hasPrefix(q) { consider(.keyword, k) }
        }
        return best
    }

    static func isSubsequence(_ q: String, of s: String) -> Bool {
        var it = s.makeIterator()
        outer: for c in q {
            while let x = it.next() { if x == c { continue outer } }
            return false
        }
        return true
    }
}
