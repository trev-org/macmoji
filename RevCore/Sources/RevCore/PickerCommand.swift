import Foundation

/// A reusable command shown alongside emoji in the inline `:` picker.
public struct PickerCommand: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Exact shortcode-style names that may trigger this command on a closing colon.
    public let aliases: [String]
    public let keywords: [String]
    /// An SF Symbol name interpreted by the macOS app target.
    public let systemImageName: String

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        keywords: [String] = [],
        systemImageName: String
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.keywords = keywords
        self.systemImageName = systemImageName
    }
}

public enum PickerCommandMatchTier: Int, Comparable, Sendable {
    case exact = 0
    case prefix
    case substring
    case fuzzy

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct PickerCommandMatch: Equatable, Sendable {
    public let command: PickerCommand
    public let matchedTerm: String
    public let tier: PickerCommandMatchTier

    /// Exact/prefix command matches are placed before emoji; weaker matches follow emoji.
    public var isPriority: Bool { tier == .exact || tier == .prefix }
}

public enum PickerSearchResult: Equatable, Identifiable, Sendable {
    case emoji(EmojiSearch.Result)
    case command(PickerCommandMatch)

    public var id: String {
        switch self {
        case .emoji(let result): return "emoji:\(result.emoji.id)"
        case .command(let match): return "command:\(match.command.id)"
        }
    }
}

public struct PickerSearch: Sendable {
    public let emojiSearch: EmojiSearch
    public let commands: [PickerCommand]

    public init(emojiSearch: EmojiSearch, commands: [PickerCommand]) {
        self.emojiSearch = emojiSearch
        self.commands = commands
    }

    /// Returns all matching commands in addition to up to `emojiLimit` emoji.
    ///
    /// Exact/prefix command matches lead the list. Substring/fuzzy command matches are appended
    /// after emoji, so commands never acquire or interfere with emoji frecency.
    public func search(_ query: String, emojiLimit: Int = 8) -> [PickerSearchResult] {
        let commandMatches = Self.commandMatches(query, commands: commands)
        let priority = commandMatches.filter(\.isPriority).map(PickerSearchResult.command)
        let secondary = commandMatches.filter { !$0.isPriority }.map(PickerSearchResult.command)
        let emoji = emojiSearch.search(query, limit: emojiLimit).map(PickerSearchResult.emoji)
        return priority + emoji + secondary
    }

    public func exactCommand(named name: String) -> PickerCommand? {
        let normalized = Self.normalizedTerm(name)
        return commands.first { command in
            ([Self.normalizedTerm(command.name)] + command.aliases.map(Self.normalizedTerm))
                .contains(normalized)
        }
    }

    public static func commandMatches(
        _ rawQuery: String,
        commands: [PickerCommand]
    ) -> [PickerCommandMatch] {
        let query = normalizedTerm(rawQuery)
        guard !query.isEmpty else { return [] }

        return commands.compactMap { command in
            let terms = [command.name] + command.aliases + command.keywords
            let matches = terms.compactMap { term -> PickerCommandMatch? in
                let normalized = normalizedTerm(term)
                let tier: PickerCommandMatchTier
                if normalized == query {
                    tier = .exact
                } else if normalized.hasPrefix(query) {
                    tier = .prefix
                } else if normalized.contains(query) {
                    tier = .substring
                } else if EmojiSearch.isSubsequence(query, of: normalized) {
                    tier = .fuzzy
                } else {
                    return nil
                }
                return PickerCommandMatch(command: command, matchedTerm: term, tier: tier)
            }
            return matches.min {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                return $0.matchedTerm.count < $1.matchedTerm.count
            }
        }.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.command.name.count != $1.command.name.count {
                return $0.command.name.count < $1.command.name.count
            }
            return $0.command.name < $1.command.name
        }
    }

    private static func normalizedTerm(_ value: String) -> String {
        value.lowercased().map {
            $0.isLetter || $0.isNumber ? String($0) : "_"
        }.joined()
        .split(separator: "_", omittingEmptySubsequences: true)
        .joined(separator: "_")
    }
}
