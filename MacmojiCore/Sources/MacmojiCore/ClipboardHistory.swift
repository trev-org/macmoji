import Foundation

public struct ClipboardSource: Codable, Equatable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var name: String?

    public init(bundleIdentifier: String?, name: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

public enum ClipboardImageFormat: String, Codable, CaseIterable, Sendable {
    case png
    case tiff

    public var fileExtension: String { rawValue }
}

public struct ClipboardImage: Codable, Equatable, Hashable, Sendable {
    public let blobName: String
    public let thumbnailBlobName: String?
    public let format: ClipboardImageFormat
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let byteCount: Int
    public let contentHash: String

    public init(
        blobName: String,
        thumbnailBlobName: String?,
        format: ClipboardImageFormat,
        pixelWidth: Int?,
        pixelHeight: Int?,
        byteCount: Int,
        contentHash: String
    ) {
        self.blobName = blobName
        self.thumbnailBlobName = thumbnailBlobName
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.contentHash = contentHash
    }
}

public enum ClipboardItemKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case link
    case files
    case color
}

public enum ClipboardContent: Codable, Equatable, Hashable, Sendable {
    case text(String)
    case link(String)
    case files([String])
    case image(ClipboardImage)
    case color(String)

    public var kind: ClipboardItemKind {
        switch self {
        case .text: return .text
        case .link: return .link
        case .files: return .files
        case .image: return .image
        case .color: return .color
        }
    }

    public var characterCount: Int? {
        switch self {
        case .text(let value), .link(let value), .color(let value):
            return value.count
        case .files, .image:
            return nil
        }
    }

    public var displayText: String {
        switch self {
        case .text(let value), .link(let value), .color(let value):
            return value
        case .files(let values):
            return values.joined(separator: "\n")
        case .image(let image):
            if let width = image.pixelWidth, let height = image.pixelHeight {
                return "Image \(width)×\(height)"
            }
            return "Image"
        }
    }

    var searchableValues: [String] {
        switch self {
        case .text(let value), .link(let value), .color(let value):
            return [value]
        case .files(let values):
            return values + values.map { URL(fileURLWithPath: $0).lastPathComponent }
        case .image:
            return ["image"]
        }
    }

    var blobNames: Set<String> {
        guard case .image(let image) = self else { return [] }
        var names = Set([image.blobName])
        if let thumbnail = image.thumbnailBlobName { names.insert(thumbnail) }
        return names
    }
}

public struct ClipboardItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var content: ClipboardContent
    public var source: ClipboardSource
    public var copiedAt: Date
    public var isPinned: Bool
    public let deduplicationKey: String

    public init(
        id: UUID,
        content: ClipboardContent,
        source: ClipboardSource,
        copiedAt: Date,
        isPinned: Bool = false,
        deduplicationKey: String
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.deduplicationKey = deduplicationKey
    }

    public var kind: ClipboardItemKind { content.kind }
}

/// Transient content captured from a platform pasteboard before blobs are persisted.
public enum ClipboardCaptureContent: Equatable, Sendable {
    case text(String)
    case link(String)
    case files([String])
    case image(
        data: Data,
        thumbnailData: Data?,
        format: ClipboardImageFormat,
        pixelWidth: Int?,
        pixelHeight: Int?
    )
    case color(String)

    /// Classifies plain text as a color or URL when possible, otherwise as text.
    public static func classify(text: String) -> ClipboardCaptureContent? {
        guard !text.isEmpty else { return nil }
        if let color = ClipboardColor.normalizedHex(text) { return .color(color) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(where: \.isWhitespace),
           let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased(),
           ["http", "https", "mailto", "ftp"].contains(scheme) {
            return .link(trimmed)
        }
        return .text(text)
    }
}

public enum ClipboardColor {
    /// Supports the common #RGB, #RGBA, #RRGGBB and #RRGGBBAA forms.
    public static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#" else { return nil }
        let digits = trimmed.dropFirst()
        guard [3, 4, 6, 8].contains(digits.count),
              digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + digits.uppercased()
    }
}

public enum ClipboardRetention: String, Codable, CaseIterable, Sendable {
    case oneDay
    case sevenDays
    case thirtyDays
    case threeMonths
    case unlimited

    public var interval: TimeInterval? {
        switch self {
        case .oneDay: return 24 * 60 * 60
        case .sevenDays: return 7 * 24 * 60 * 60
        case .thirtyDays: return 30 * 24 * 60 * 60
        case .threeMonths: return 90 * 24 * 60 * 60
        case .unlimited: return nil
        }
    }

    public var label: String {
        switch self {
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .threeMonths: return "3 months"
        case .unlimited: return "Unlimited"
        }
    }
}

public struct ClipboardHistoryConfiguration: Equatable, Sendable {
    public var retention: ClipboardRetention
    public var maximumUnpinnedEntries: Int

    public init(retention: ClipboardRetention = .sevenDays, maximumUnpinnedEntries: Int = 1_000) {
        precondition(maximumUnpinnedEntries > 0)
        self.retention = retention
        self.maximumUnpinnedEntries = maximumUnpinnedEntries
    }
}

public enum ClipboardTypeFilter: String, CaseIterable, Sendable {
    case all
    case text
    case images
    case links
    case files

    public var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .links: return "Links"
        case .files: return "Files"
        }
    }

    func includes(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text || item.kind == .color
        case .images: return item.kind == .image
        case .links: return item.kind == .link
        case .files: return item.kind == .files
        }
    }
}

public enum ClipboardHistorySearch {
    public static func results(
        in items: [ClipboardItem],
        query rawQuery: String,
        filter: ClipboardTypeFilter = .all
    ) -> [ClipboardItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var matches: [(item: ClipboardItem, quality: Int)] = []

        for item in items where filter.includes(item) {
            let quality: Int
            if query.isEmpty {
                quality = 0
            } else {
                let fields = item.content.searchableValues
                    + [item.source.name, item.source.bundleIdentifier].compactMap { $0 }
                let qualities = fields.compactMap { matchQuality(query, in: $0.lowercased()) }
                guard let best = qualities.min() else { continue }
                quality = best
            }
            matches.append((item, quality))
        }

        matches.sort { lhs, rhs in
            if lhs.item.isPinned != rhs.item.isPinned { return lhs.item.isPinned }
            if lhs.quality != rhs.quality { return lhs.quality < rhs.quality }
            if lhs.item.copiedAt != rhs.item.copiedAt { return lhs.item.copiedAt > rhs.item.copiedAt }
            return lhs.item.id.uuidString < rhs.item.id.uuidString
        }
        return matches.map(\.item)
    }

    /// Substring matches rank before fuzzy subsequence matches.
    static func matchQuality(_ query: String, in candidate: String) -> Int? {
        if candidate.contains(query) { return 0 }
        return isSubsequence(query, of: candidate) ? 1 : nil
    }

    static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var iterator = candidate.makeIterator()
        outer: for character in query {
            while let next = iterator.next() {
                if next == character { continue outer }
            }
            return false
        }
        return true
    }
}

public enum ClipboardPrivacy {
    public static let sensitiveTypeIdentifiers: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    public static let defaultExcludedBundleIdentifiers = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.lastpass.LastPass",
        "com.lastpass.LastPass-Desktop",
        "com.dashlane.Dashlane",
    ]

    public static func shouldCapture(
        typeIdentifiers: [String],
        sourceBundleIdentifier: String?,
        excludedBundleIdentifiers: [String]
    ) -> Bool {
        if !sensitiveTypeIdentifiers.isDisjoint(with: typeIdentifiers) { return false }
        guard let sourceBundleIdentifier else { return true }
        return !excludedBundleIdentifiers.contains {
            $0.caseInsensitiveCompare(sourceBundleIdentifier) == .orderedSame
        }
    }
}
