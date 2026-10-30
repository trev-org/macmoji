import Foundation

public struct RevTool: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let keywords: [String]
    public let systemImageName: String

    public init(
        id: String,
        name: String,
        keywords: [String] = [],
        systemImageName: String
    ) {
        self.id = id
        self.name = name
        self.keywords = keywords
        self.systemImageName = systemImageName
    }
}

/// Ordered registry backing the Tools launcher. Future features can register another tool.
public struct ToolRegistry: Sendable {
    public private(set) var tools: [RevTool] = []

    public init(tools: [RevTool] = []) {
        for tool in tools { register(tool) }
    }

    public mutating func register(_ tool: RevTool) {
        if let index = tools.firstIndex(where: { $0.id == tool.id }) {
            tools[index] = tool
        } else {
            tools.append(tool)
        }
    }

    public func search(_ rawQuery: String) -> [RevTool] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tools }

        return tools.enumerated().compactMap { index, tool -> (RevTool, Int, Int)? in
            let qualities = ([tool.name] + tool.keywords).compactMap {
                Self.matchQuality(query, candidate: $0.lowercased())
            }
            guard let quality = qualities.min() else { return nil }
            return (tool, quality, index)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }.map(\.0)
    }

    private static func matchQuality(_ query: String, candidate: String) -> Int? {
        if candidate == query { return 0 }
        if candidate.hasPrefix(query) { return 1 }
        if candidate.contains(query) { return 2 }
        return EmojiSearch.isSubsequence(query, of: candidate) ? 3 : nil
    }
}
