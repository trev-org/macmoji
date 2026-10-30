import Dispatch
import Foundation

public protocol SnippetStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

public struct JSONFileSnippetStorage: SnippetStorage, @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return applicationSupport
            .appendingPathComponent("Macmoji", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum SnippetStoreError: Error, Equatable, LocalizedError {
    case emptyName
    case emptyText
    case invalidKeyword
    case duplicateKeyword(String)
    case missingSnippet
    case invalidImport
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Name is required."
        case .emptyText: return "Snippet text is required."
        case .invalidKeyword: return "Keywords cannot contain newlines or control characters."
        case .duplicateKeyword(let keyword): return "The keyword “\(keyword)” is already in use."
        case .missingSnippet: return "The snippet no longer exists."
        case .invalidImport: return "This file is not a supported snippets JSON file."
        case .unsupportedVersion(let version):
            return "Snippet file version \(version) is not supported."
        }
    }
}

public struct SnippetImportSummary: Equatable, Sendable {
    public let importedCount: Int
    public let skippedCount: Int

    public init(importedCount: Int, skippedCount: Int) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
    }
}

/// Thread-safe snippet storage with versioned, serialized background persistence.
public final class SnippetStore: @unchecked Sendable {
    private struct Payload: Codable {
        let version: Int
        let snippets: [Snippet]

        init(snippets: [Snippet]) {
            version = 1
            self.snippets = snippets
        }
    }

    private struct RaycastSnippet: Decodable {
        let name: String
        let text: String
        let keyword: String?
    }

    private enum ImportSource {
        case native([Snippet])
        case raycast([RaycastSnippet])
    }

    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "com.trevorgerald.macmoji.snippet-persistence",
        qos: .utility
    )
    private let storage: (any SnippetStorage)?
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var storedSnippets: [Snippet]

    public init(
        storage: (any SnippetStorage)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.storage = storage
        self.now = now
        self.makeID = makeID
        storedSnippets = Self.load(from: storage)
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storedSnippets.count
    }

    public func allSnippets() -> [Snippet] {
        lock.lock(); defer { lock.unlock() }
        return storedSnippets
    }

    public func snippet(id: UUID) -> Snippet? {
        lock.lock(); defer { lock.unlock() }
        return storedSnippets.first { $0.id == id }
    }

    public func snippetsWithKeywords() -> [Snippet] {
        lock.lock(); defer { lock.unlock() }
        return storedSnippets.filter { $0.keyword?.isEmpty == false }
    }

    public func search(_ query: String) -> [Snippet] {
        let timestamp = now()
        lock.lock()
        let snapshot = storedSnippets
        lock.unlock()
        return SnippetSearch.results(in: snapshot, query: query, at: timestamp)
    }

    @discardableResult
    public func create(name: String, text: String, keyword: String?) throws -> Snippet {
        lock.lock()
        do {
            let fields = try normalizedFields(name: name, text: text, keyword: keyword)
            try validateUniqueKeyword(fields.keyword, excluding: nil)
            let timestamp = now()
            let snippet = Snippet(
                id: makeID(),
                name: fields.name,
                text: fields.text,
                keyword: fields.keyword,
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            storedSnippets.append(snippet)
            schedulePersistence(storedSnippets)
            lock.unlock()
            return snippet
        } catch {
            lock.unlock()
            throw error
        }
    }

    @discardableResult
    public func update(
        id: UUID,
        name: String,
        text: String,
        keyword: String?
    ) throws -> Snippet {
        lock.lock()
        do {
            guard let index = storedSnippets.firstIndex(where: { $0.id == id }) else {
                throw SnippetStoreError.missingSnippet
            }
            let fields = try normalizedFields(name: name, text: text, keyword: keyword)
            try validateUniqueKeyword(fields.keyword, excluding: id)
            storedSnippets[index].name = fields.name
            storedSnippets[index].text = fields.text
            storedSnippets[index].keyword = fields.keyword
            storedSnippets[index].modifiedAt = max(storedSnippets[index].modifiedAt, now())
            let snippet = storedSnippets[index]
            schedulePersistence(storedSnippets)
            lock.unlock()
            return snippet
        } catch {
            lock.unlock()
            throw error
        }
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        lock.lock()
        let originalCount = storedSnippets.count
        storedSnippets.removeAll { $0.id == id }
        guard storedSnippets.count != originalCount else {
            lock.unlock()
            return false
        }
        schedulePersistence(storedSnippets)
        lock.unlock()
        return true
    }

    @discardableResult
    public func recordUse(id: UUID) -> Snippet? {
        lock.lock()
        guard let index = storedSnippets.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return nil
        }
        if storedSnippets[index].useCount < Int.max {
            storedSnippets[index].useCount += 1
        }
        let timestamp = now()
        if let previous = storedSnippets[index].lastUsedAt {
            storedSnippets[index].lastUsedAt = max(previous, timestamp)
        } else {
            storedSnippets[index].lastUsedAt = timestamp
        }
        let snippet = storedSnippets[index]
        schedulePersistence(storedSnippets)
        lock.unlock()
        return snippet
    }

    public func exportData() throws -> Data {
        lock.lock()
        let snapshot = storedSnippets
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Payload(snippets: snapshot))
    }

    @discardableResult
    public func importData(_ data: Data) throws -> SnippetImportSummary {
        let decoder = JSONDecoder()
        let source: ImportSource
        if let payload = try? decoder.decode(Payload.self, from: data) {
            guard payload.version == 1 else {
                throw SnippetStoreError.unsupportedVersion(payload.version)
            }
            source = .native(payload.snippets)
        } else if let raycast = try? decoder.decode([RaycastSnippet].self, from: data) {
            source = .raycast(raycast)
        } else {
            throw SnippetStoreError.invalidImport
        }

        lock.lock()
        let summary: SnippetImportSummary
        switch source {
        case .native(let snippets):
            summary = importNative(snippets)
        case .raycast(let snippets):
            summary = importRaycast(snippets)
        }
        if summary.importedCount > 0 { schedulePersistence(storedSnippets) }
        lock.unlock()
        return summary
    }

    /// Waits for all writes queued before this call.
    public func flush() {
        lock.lock()
        persistenceQueue.sync {}
        lock.unlock()
    }

    private func importNative(_ snippets: [Snippet]) -> SnippetImportSummary {
        var imported = 0
        var skipped = 0
        for candidate in snippets {
            do {
                let fields = try normalizedFields(
                    name: candidate.name,
                    text: candidate.text,
                    keyword: candidate.keyword
                )
                let existingIndex = storedSnippets.firstIndex { $0.id == candidate.id }
                try validateUniqueKeyword(fields.keyword, excluding: candidate.id)
                let normalized = Snippet(
                    id: candidate.id,
                    name: fields.name,
                    text: fields.text,
                    keyword: fields.keyword,
                    createdAt: candidate.createdAt,
                    modifiedAt: candidate.modifiedAt,
                    lastUsedAt: candidate.lastUsedAt,
                    useCount: max(0, candidate.useCount)
                )
                if let existingIndex {
                    storedSnippets[existingIndex] = normalized
                } else {
                    storedSnippets.append(normalized)
                }
                imported += 1
            } catch {
                skipped += 1
            }
        }
        return SnippetImportSummary(importedCount: imported, skippedCount: skipped)
    }

    private func importRaycast(_ snippets: [RaycastSnippet]) -> SnippetImportSummary {
        var imported = 0
        var skipped = 0
        for candidate in snippets {
            do {
                let fields = try normalizedFields(
                    name: candidate.name,
                    text: candidate.text,
                    keyword: candidate.keyword
                )
                try validateUniqueKeyword(fields.keyword, excluding: nil)
                let timestamp = now()
                storedSnippets.append(Snippet(
                    id: makeID(),
                    name: fields.name,
                    text: fields.text,
                    keyword: fields.keyword,
                    createdAt: timestamp,
                    modifiedAt: timestamp
                ))
                imported += 1
            } catch {
                skipped += 1
            }
        }
        return SnippetImportSummary(importedCount: imported, skippedCount: skipped)
    }

    private func normalizedFields(
        name: String,
        text: String,
        keyword: String?
    ) throws -> (name: String, text: String, keyword: String?) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw SnippetStoreError.emptyName }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SnippetStoreError.emptyText
        }
        let normalizedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalKeyword = normalizedKeyword?.isEmpty == false ? normalizedKeyword : nil
        if let finalKeyword, finalKeyword.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }) {
            throw SnippetStoreError.invalidKeyword
        }
        return (normalizedName, text, finalKeyword)
    }

    private func validateUniqueKeyword(_ keyword: String?, excluding id: UUID?) throws {
        guard let keyword else { return }
        if storedSnippets.contains(where: { $0.id != id && $0.keyword == keyword }) {
            throw SnippetStoreError.duplicateKeyword(keyword)
        }
    }

    private func schedulePersistence(_ snippets: [Snippet]) {
        guard let storage else { return }
        persistenceQueue.async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(Payload(snippets: snippets)) else { return }
            try? storage.save(data)
        }
    }

    private static func load(from storage: (any SnippetStorage)?) -> [Snippet] {
        guard let storage,
              let data = try? storage.load(),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1 else { return [] }

        var ids = Set<UUID>()
        var keywords = Set<String>()
        return payload.snippets.filter { snippet in
            guard !snippet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  snippet.useCount >= 0,
                  snippet.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  snippet.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
                  snippet.lastUsedAt?.timeIntervalSinceReferenceDate.isFinite != false,
                  ids.insert(snippet.id).inserted else { return false }
            guard let keyword = snippet.keyword, !keyword.isEmpty else { return true }
            return keywords.insert(keyword).inserted
        }
    }
}
