import Foundation

public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var text: String
    public var keyword: String?
    public let createdAt: Date
    public var modifiedAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        text: String,
        keyword: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.keyword = keyword
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

public struct SnippetKeywordMatch: Equatable, Sendable {
    public let snippetID: UUID
    public let keyword: String

    public init(snippetID: UUID, keyword: String) {
        self.snippetID = snippetID
        self.keyword = keyword
    }

    public var deleteCount: Int { keyword.count }
}

/// Tracks recently typed characters and reports exact keyword suffix matches.
///
/// The caller owns lifecycle resets (focus changes, clicks and navigation keys), which keeps
/// this type portable and lets the event tap decide what constitutes a new typing context.
public struct SnippetKeywordBuffer: Sendable {
    private var characters: [Character] = []

    public init() {}

    public mutating func reset() {
        characters.removeAll(keepingCapacity: true)
    }

    public mutating func backspace() {
        if !characters.isEmpty { characters.removeLast() }
    }

    public mutating func type(
        _ character: Character,
        snippets: [Snippet],
        requiresWordBoundary: Bool
    ) -> SnippetKeywordMatch? {
        let candidates = snippets.compactMap { snippet -> (Snippet, [Character])? in
            guard let keyword = snippet.keyword, !keyword.isEmpty else { return nil }
            return (snippet, Array(keyword))
        }
        guard let longest = candidates.map({ $0.1.count }).max() else {
            reset()
            return nil
        }

        characters.append(character)
        let retainedCount = longest + (requiresWordBoundary ? 1 : 0)
        if characters.count > retainedCount {
            characters.removeFirst(characters.count - retainedCount)
        }

        // Prefer the longest suffix when imported data contains overlapping keywords.
        for (snippet, keywordCharacters) in candidates.sorted(by: { $0.1.count > $1.1.count }) {
            guard characters.count >= keywordCharacters.count,
                  Array(characters.suffix(keywordCharacters.count)) == keywordCharacters else {
                continue
            }
            if requiresWordBoundary, characters.count > keywordCharacters.count {
                let preceding = characters[characters.count - keywordCharacters.count - 1]
                guard !Self.isWordCharacter(preceding) else { continue }
            }
            reset()
            return SnippetKeywordMatch(snippetID: snippet.id, keyword: String(keywordCharacters))
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}

public enum SnippetSearch {
    public static let defaultHalfLife: TimeInterval = 7 * 24 * 60 * 60

    public static func results(
        in snippets: [Snippet],
        query rawQuery: String,
        at now: Date = Date(),
        halfLife: TimeInterval = defaultHalfLife
    ) -> [Snippet] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = snippets.compactMap { snippet -> (Snippet, Int, Double)? in
            let quality: Int
            if query.isEmpty {
                quality = 0
            } else {
                let qualities = [
                    matchQuality(query, in: snippet.name, fieldPenalty: 0),
                    snippet.keyword.flatMap { matchQuality(query, in: $0, fieldPenalty: 0) },
                    matchQuality(query, in: snippet.text, fieldPenalty: 3),
                ].compactMap { $0 }
                guard let best = qualities.min() else { return nil }
                quality = best
            }
            return (snippet, quality, frecency(of: snippet, at: now, halfLife: halfLife))
        }

        return matches.sorted { lhs, rhs in
            let lhsUsed = lhs.2 > 0
            let rhsUsed = rhs.2 > 0
            if lhsUsed != rhsUsed { return lhsUsed }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.modifiedAt != rhs.0.modifiedAt { return lhs.0.modifiedAt > rhs.0.modifiedAt }
            if lhs.0.name != rhs.0.name {
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }.map(\.0)
    }

    private static func matchQuality(
        _ query: String,
        in rawCandidate: String,
        fieldPenalty: Int
    ) -> Int? {
        let candidate = rawCandidate.lowercased()
        if candidate == query { return fieldPenalty }
        if candidate.hasPrefix(query) { return fieldPenalty + 1 }
        if candidate.contains(query) { return fieldPenalty + 2 }
        return isSubsequence(query, of: candidate) ? fieldPenalty + 5 : nil
    }

    private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var iterator = candidate.makeIterator()
        outer: for character in query {
            while let next = iterator.next() {
                if next == character { continue outer }
            }
            return false
        }
        return true
    }

    private static func frecency(
        of snippet: Snippet,
        at now: Date,
        halfLife: TimeInterval
    ) -> Double {
        guard snippet.useCount > 0, let lastUsedAt = snippet.lastUsedAt, halfLife > 0 else {
            return 0
        }
        let elapsed = now.timeIntervalSince(lastUsedAt)
        let age = elapsed.isFinite ? max(0, elapsed) : 0
        return log2(Double(snippet.useCount) + 1) * pow(0.5, age / halfLife)
    }
}
