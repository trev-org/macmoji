import Foundation

public struct SnippetExpansion: Equatable, Sendable {
    public let text: String
    /// Number of left-arrow presses required to place the caret at `{cursor}`.
    public let cursorOffset: Int

    public init(text: String, cursorOffset: Int) {
        self.text = text
        self.cursorOffset = cursorOffset
    }
}

public struct SnippetExpansionContext {
    public var clipboard: String
    public var date: Date
    public var calendar: Calendar
    public var locale: Locale
    public var timeZone: TimeZone

    public init(
        clipboard: String = "",
        date: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.clipboard = clipboard
        self.date = date
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
    }
}

public enum SnippetExpansionEngine {
    /// Expands Raycast-style placeholders. Unknown placeholders are preserved literally.
    ///
    /// Date placeholders also accept `format` and a compact `offset`, for example
    /// `{date format="yyyy-MM-dd" offset="+2d"}`. Offset units are seconds (`s`), minutes
    /// (`m`), hours (`h`), days (`d`), weeks (`w`), months (`M`) and years (`y`).
    public static func expand(
        _ template: String,
        context: SnippetExpansionContext = SnippetExpansionContext()
    ) -> SnippetExpansion {
        var output = ""
        var cursorPosition: Int?
        var index = template.startIndex

        while index < template.endIndex {
            guard template[index] == "{",
                  let close = template[index...].firstIndex(of: "}") else {
                output.append(template[index])
                index = template.index(after: index)
                continue
            }

            let bodyStart = template.index(after: index)
            let body = String(template[bodyStart..<close])
            if body == "cursor" {
                if cursorPosition == nil { cursorPosition = output.count }
            } else if let replacement = replacement(for: body, context: context) {
                output += replacement
            } else {
                output += String(template[index...close])
            }
            index = template.index(after: close)
        }

        let offset = cursorPosition.map { max(0, output.count - $0) } ?? 0
        return SnippetExpansion(text: output, cursorOffset: offset)
    }

    private static func replacement(
        for body: String,
        context: SnippetExpansionContext
    ) -> String? {
        if body == "clipboard" { return context.clipboard }

        let parts = body.split(
            maxSplits: 1,
            omittingEmptySubsequences: true,
            whereSeparator: \.isWhitespace
        )
        guard let first = parts.first else { return nil }
        let kind = String(first)
        guard ["date", "time", "datetime", "day"].contains(kind) else { return nil }

        let attributes = parts.count > 1 ? parseAttributes(String(parts[1])) : [:]
        let adjustedDate = attributes["offset"].flatMap {
            date(byApplying: $0, to: context.date, calendar: context.calendar)
        } ?? context.date
        let defaultFormat: String
        switch kind {
        case "date": defaultFormat = "yyyy-MM-dd"
        case "time": defaultFormat = "HH:mm"
        case "datetime": defaultFormat = "yyyy-MM-dd HH:mm"
        default: defaultFormat = "EEEE"
        }

        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.calendar = context.calendar
        formatter.timeZone = context.timeZone
        formatter.dateFormat = attributes["format"] ?? defaultFormat
        return formatter.string(from: adjustedDate)
    }

    private static func parseAttributes(_ value: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"([A-Za-z]+)\s*=\s*"([^"]*)""#
        ) else { return [:] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var result: [String: String] = [:]
        for match in expression.matches(in: value, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: value),
                  let valueRange = Range(match.range(at: 2), in: value) else { continue }
            result[String(value[keyRange])] = String(value[valueRange])
        }
        return result
    }

    private static func date(
        byApplying offset: String,
        to date: Date,
        calendar originalCalendar: Calendar
    ) -> Date? {
        guard offset.count >= 2, let unit = offset.last else { return nil }
        let amountText = String(offset.dropLast())
        guard let amount = Int(amountText) else { return nil }
        let component: Calendar.Component
        switch unit {
        case "s": component = .second
        case "m": component = .minute
        case "h": component = .hour
        case "d": component = .day
        case "w": component = .weekOfYear
        case "M": component = .month
        case "y": component = .year
        default: return nil
        }
        return originalCalendar.date(byAdding: component, value: amount, to: date)
    }
}
