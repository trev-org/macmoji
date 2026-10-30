/// Character rules for the ':' trigger (plan decision 5).
public enum ShortcodeRules {
    /// Characters allowed inside a shortcode query: [a-z0-9_+-].
    public static func isShortcodeChar(_ c: Character) -> Bool {
        guard c.isASCII, let a = c.asciiValue else { return false }
        return (a >= 97 && a <= 122) || (a >= 48 && a <= 57) || c == "_" || c == "+" || c == "-"
    }

    /// ':' only arms after start-of-text, whitespace, '(' or '['.
    public static func isBoundary(_ previous: Character?) -> Bool {
        guard let p = previous else { return true }
        return p.isWhitespace || p == "(" || p == "["
    }

    /// Characters that cancel when typed immediately after ':' (space, '/', digits) or are not shortcode chars.
    public static func cancelsRightAfterColon(_ c: Character) -> Bool {
        c.isWhitespace || c == "/" || c.isNumber || !isShortcodeChar(c)
    }

    /// Minimum query length before the picker opens.
    public static let minimumQueryLength = 2
}
