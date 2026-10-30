import Foundation

/// Default skin tone applied to emoji that support skin modifiers.
public enum SkinTone: Int, CaseIterable, Codable, Sendable {
    case none = 0, light, mediumLight, medium, mediumDark, dark

    public var label: String {
        switch self {
        case .none: return "Default (yellow)"
        case .light: return "Light"
        case .mediumLight: return "Medium-light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium-dark"
        case .dark: return "Dark"
        }
    }
}

public struct Emoji: Hashable, Sendable, Identifiable {
    /// Base emoji (no skin tone).
    public let emoji: String
    /// Shortcodes; `names[0]` is the primary (iamcal/Slack) name, the rest are aliases (GitHub).
    public let names: [String]
    /// Emojibase tags used for keyword search.
    public let keywords: [String]
    /// Five skin-tone variants (light ... dark), if the emoji supports them.
    public let skins: [String]?
    /// Emojibase display order.
    public let order: Int

    public var id: String { emoji }
    public var primaryName: String { names.first ?? "" }

    public init(emoji: String, names: [String], keywords: [String] = [], skins: [String]? = nil, order: Int = 0) {
        self.emoji = emoji
        self.names = names
        self.keywords = keywords
        self.skins = skins
        self.order = order
    }

    /// The emoji string to insert for a given default skin tone.
    public func rendered(tone: SkinTone) -> String {
        guard tone != .none, let skins, skins.count == 5 else { return emoji }
        return skins[tone.rawValue - 1]
    }
}
